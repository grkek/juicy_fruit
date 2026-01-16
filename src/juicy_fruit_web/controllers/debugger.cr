module JuicyFruitWeb
  module Controllers
    # Provides a JSON-based protocol for controlling the VirtualMachine debugger
    # over WebSocket connections.
    class Debugger
      include Grip::Controllers::WebSocket

      alias VirtualMachine = Jelly::VirtualMachine
      alias Action = VirtualMachine::Engine::Debugger::Action

      class Session
        property engine : VirtualMachine::Engine?
        property debugger : VirtualMachine::Engine::Debugger?
        property pending_action : Channel(Action)
        property breakpoints : Hash(String, VirtualMachine::Engine::Debugger::Breakpoint)
        property is_running : Bool
        property current_process : VirtualMachine::Process?
        property loaded_instructions : Array(VirtualMachine::Instruction)?

        def initialize
          @pending_action = Channel(Action).new(1)
          @breakpoints = {} of String => VirtualMachine::Engine::Debugger::Breakpoint
          @is_running = false
        end

        def cleanup
          @pending_action.close rescue nil
          @engine = nil
          @debugger = nil
        end
      end

      property connections : Hash(Socket, Session) = {} of Socket => Session
      property mutex : Mutex = Mutex.new

      def on_open(context : Context, socket : Socket) : Void
        session = Session.new

        mutex.synchronize do
          connections[socket] = session
        end

        send_json(socket, {
          "type"    => "connected",
          "message" => "Jelly VirtualMachine debugger session initialized",
        })
      end

      def on_message(context : Context, socket : Socket, message : String) : Void
        session = get_session(socket)
        return unless session

        begin
          request = JSON.parse(message)
          command = request["command"]?.try(&.as_s) || ""
          handle_command(socket, session, command, request)
        rescue ex : JSON::ParseException
          send_error(socket, "invalidJson", "Invalid JSON: #{ex.message}")
        rescue ex
          send_error(socket, "commandError", "Error processing command: #{ex.message}")
        end
      end

      def on_ping(context : Context, socket : Socket, message : String) : Void
        socket.pong(message)
      end

      def on_pong(context : Context, socket : Socket, message : String) : Void
      end

      def on_binary(context : Context, socket : Socket, binary : Bytes) : Void
        send_error(socket, "unsupportedFormat", "Binary messages are not supported")
      end

      def on_close(context : Context, socket : Socket, close_code : HTTP::WebSocket::CloseCode | Int?, message : String) : Void
        session = remove_session(socket)
        return unless session

        if session.is_running
          session.pending_action.send(Action::Abort) rescue nil
        end
        session.cleanup
      end

      private def handle_command(socket : Socket, session : Session, command : String, request : JSON::Any) : Void
        case command
        when "init"
          handle_init(socket, session, request)
        when "load"
          handle_load(socket, session, request)
        when "run"
          handle_run(socket, session)
        when "step"
          handle_step(socket, session)
        when "continue"
          handle_continue(socket, session)
        when "abort"
          handle_abort(socket, session)
        when "addBreakpoint"
          handle_add_breakpoint(socket, session, request)
        when "removeBreakpoint"
          handle_remove_breakpoint(socket, session, request)
        when "getState"
          handle_get_state(socket, session)
        when "listBreakpoints"
          handle_list_breakpoints(socket, session)
        when "evaluate"
          handle_evaluate(socket, session, request)
        else
          send_error(socket, "unknownCommand", "Unknown command: #{command}")
        end
      end

      private def handle_init(socket : Socket, session : Session, request : JSON::Any) : Void
        if session.engine
          send_error(socket, "alreadyInitialized", "Engine already initialized")
          return
        end

        engine = VirtualMachine::Engine.new

        # Override PRINT_LINE to capture output and send to WebSocket
        # Must replicate full behavior including counter increment
        engine.on_instruction(VirtualMachine::Code::PRINT_LINE) do |process, instruction|
          process.counter += 1

          if process.stack.empty?
            raise Jelly::VirtualMachine::EmulationException.new("Stack underflow for PRINT_LINE")
          end

          value = process.stack.pop
          output = value.to_s

          # Send to WebSocket
          send_json(socket, {
            "type" => "stdout",
            "data" => output,
          })

          # Also print to server console
          puts output

          VirtualMachine::Value.new(nil)
        end

        # Override PRINT if it exists
        {% if Jelly::VirtualMachine::Code.constants.map(&.stringify).includes?("PRINT") %}
          engine.on_instruction(VirtualMachine::Code::PRINT) do |process, instruction|
            process.counter += 1

            if process.stack.empty?
              raise Jelly::VirtualMachine::EmulationException.new("Stack underflow for PRINT")
            end

            value = process.stack.pop
            output = value.to_s

            send_json(socket, {
              "type" => "stdout",
              "data" => output,
            })

            print output

            VirtualMachine::Value.new(nil)
          end
        {% end %}

        debugger = engine.attach_debugger do |process, instruction|
          session.current_process = process

          send_json(socket, {
            "type" => "breakpointHit",
            "data" => serialize_process_state(process, instruction),
          })

          action = session.pending_action.receive
          session.current_process = nil
          action
        end

        session.engine = engine
        session.debugger = debugger

        if limit = request["iterationLimit"]?.try(&.as_i64)
          engine.configuration.iteration_limit = limit.to_i32
        end

        send_json(socket, {
          "type"    => "initialized",
          "message" => "VirtualMachine engine and debugger ready",
        })
      end

      private def handle_load(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized. Send 'init' first.")
          return
        end

        instructions_json = request["instructions"]?.try(&.as_a)
        unless instructions_json
          send_error(socket, "missingInstructions", "Missing 'instructions' array")
          return
        end

        begin
          instructions = parse_instructions(instructions_json)

          # Store instructions for reuse
          session.loaded_instructions = instructions

          # Clear any existing processes
          engine.processes.clear

          # Create fresh process
          process = engine.process_manager.create_process(instructions: instructions)
          engine.processes.push(process)

          send_json(socket, {
            "type"             => "loaded",
            "processAddress"   => process.address.to_s,
            "instructionCount" => instructions.size,
          })
        rescue ex
          send_error(socket, "parseError", "Failed to parse instructions: #{ex.message}")
        end
      end

      private def handle_run(socket : Socket, session : Session) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        instructions = session.loaded_instructions
        unless instructions
          send_error(socket, "noProgram", "No program loaded. Load a program first.")
          return
        end

        if session.is_running
          send_error(socket, "alreadyRunning", "Execution already in progress")
          return
        end

        # Reset debugger state for fresh run
        session.debugger.try &.reset
        session.is_running = true

        # Clear old processes and create a fresh one
        engine.processes.clear
        process = engine.process_manager.create_process(instructions: instructions)
        engine.processes.push(process)

        spawn do
          error_message : String? = nil

          begin
            engine.run
          rescue ex
            error_message = ex.message
          end

          session.is_running = false

          if message = error_message
            send_json(socket, {
              "type"    => "executionError",
              "message" => message,
            })
          end

          send_json(socket, {
            "type"    => "executionComplete",
            "message" => "Execution finished",
            "stats"   => {
              "faultTolerance" => engine.fault_tolerance_statistics.to_s,
            },
          })
        end

        send_json(socket, {
          "type"    => "running",
          "message" => "Execution started",
        })
      end

      private def handle_step(socket : Socket, session : Session) : Void
        unless session.is_running
          send_error(socket, "notPaused", "No execution paused at breakpoint")
          return
        end

        session.pending_action.send(Action::Step) rescue nil
      end

      private def handle_continue(socket : Socket, session : Session) : Void
        unless session.is_running
          send_error(socket, "notPaused", "No execution paused at breakpoint")
          return
        end

        session.pending_action.send(Action::Continue) rescue nil
      end

      private def handle_abort(socket : Socket, session : Session) : Void
        unless session.is_running
          send_error(socket, "notRunning", "No execution in progress")
          return
        end

        session.pending_action.send(Action::Abort) rescue nil

        send_json(socket, {
          "type"    => "aborted",
          "message" => "Execution abort requested",
        })
      end

      private def handle_add_breakpoint(socket : Socket, session : Session, request : JSON::Any) : Void
        debugger = session.debugger
        unless debugger
          send_error(socket, "notInitialized", "Debugger not initialized")
          return
        end

        condition_type = request["conditionType"]?.try(&.as_s) || "counter"
        value = request["value"]?.try(&.as_i64) || 0_i64

        breakpoint = case condition_type
                     when "counter"
                       debugger.add_breakpoint { |p| p.counter == value }
                     when "minStackDepth"
                       debugger.add_breakpoint { |p| p.call_stack.size >= value }
                     when "maxStackDepth"
                       debugger.add_breakpoint { |p| p.call_stack.size <= value }
                     when "stackSize"
                       debugger.add_breakpoint { |p| p.stack.size == value }
                     else
                       send_error(socket, "invalidCondition", "Unknown condition type: #{condition_type}")
                       return
                     end

        breakpoint_id = breakpoint.id.to_s
        session.breakpoints[breakpoint_id] = breakpoint

        send_json(socket, {
          "type"          => "breakpointAdded",
          "id"            => breakpoint_id,
          "conditionType" => condition_type,
          "value"         => value,
        })
      end

      private def handle_remove_breakpoint(socket : Socket, session : Session, request : JSON::Any) : Void
        breakpoint_id = request["id"]?.try(&.as_s)
        unless breakpoint_id
          send_error(socket, "missingId", "Missing breakpoint 'id'")
          return
        end

        if breakpoint = session.breakpoints.delete(breakpoint_id)
          result = session.debugger.try &.remove_breakpoint(breakpoint.id)

          send_json(socket, {
            "type" => "breakpointRemoved",
            "id"   => breakpoint_id,
          })
        else
          send_error(socket, "notFound", "Breakpoint not found: #{breakpoint_id}")
        end
      end

      private def handle_get_state(socket : Socket, session : Session) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        processes = engine.processes.map do |process|
          {
            "address"        => process.address.to_s,
            "counter"        => process.counter,
            "stackSize"      => process.stack.size,
            "callStackDepth" => process.call_stack.size,
          }
        end

        current = if p = session.current_process
                    serialize_process_state(p, nil)
                  end

        send_json(socket, {
          "type"            => "state",
          "isRunning"       => session.is_running,
          "processes"       => processes,
          "breakpointCount" => session.breakpoints.size,
          "currentProcess"  => current,
        })
      end

      private def handle_list_breakpoints(socket : Socket, session : Session) : Void
        breakpoints = session.breakpoints.map do |id, bp|
          {
            "id"       => id,
            "hitCount" => bp.hit_count,
          }
        end

        send_json(socket, {
          "type"        => "breakpoints",
          "breakpoints" => breakpoints,
        })
      end

      private def handle_evaluate(socket : Socket, session : Session, request : JSON::Any) : Void
        process = session.current_process
        unless process
          send_error(socket, "notPaused", "No process paused for evaluation")
          return
        end

        target = request["target"]?.try(&.as_s) || "stack"

        result = case target
                 when "stack"
                   limit = request["limit"]?.try(&.as_i64) || 20_i64
                   process.stack.reverse.first(limit.to_i).reverse.map(&.to_s)
                 when "locals"
                   process.locals.map(&.to_s)
                 when "callStack"
                   process.call_stack.map(&.to_s)
                 else
                   send_error(socket, "invalidTarget", "Unknown evaluation target: #{target}")
                   return
                 end

        send_json(socket, {
          "type"   => "evaluationResult",
          "target" => target,
          "result" => result,
        })
      end

      private def serialize_process_state(process, instruction)
        {
          "address"        => process.address.to_s,
          "counter"        => process.counter,
          "callStackDepth" => process.call_stack.size,
          "instruction"    => instruction.try(&.code.to_s) || "none",
          "stack"          => process.stack.reverse.first(10).reverse.map(&.to_s),
          "locals"         => process.locals.map(&.to_s),
        }
      end

      private def parse_instructions(json_array : Array(JSON::Any)) : Array(VirtualMachine::Instruction)
        json_array.map do |item|
          code_str = item["code"]?.try(&.as_s)
          raise "Missing 'code' in instruction" unless code_str

          code = VirtualMachine::Code.parse(code_str)
          value = parse_value(item["value"]?)

          VirtualMachine::Instruction.new(code, value)
        end
      end

      private def parse_value(json : JSON::Any?) : VirtualMachine::Value
        return VirtualMachine::Value.new(nil) if json.nil? || json.raw.nil?

        type = json["type"]?.try(&.as_s)
        raw_value = json["value"]?

        return VirtualMachine::Value.new(nil) unless type && raw_value

        case type
        when "string"
          VirtualMachine::Value.new(raw_value.as_s)
        when "integer"
          VirtualMachine::Value.new(raw_value.as_i64)
        when "float"
          VirtualMachine::Value.new(raw_value.as_f)
        when "symbol"
          VirtualMachine::Value.new(raw_value.to_s.to_symbol)
        when "unsignedInteger"
          VirtualMachine::Value.new(raw_value.as_i64.to_u64)
        when "bool"
          VirtualMachine::Value.new(raw_value.as_bool)
        else
          VirtualMachine::Value.new(nil)
        end
      end

      private def get_session(socket : Socket) : Session?
        mutex.synchronize do
          connections[socket]?
        end
      end

      private def remove_session(socket : Socket) : Session?
        mutex.synchronize do
          connections.delete(socket)
        end
      end

      private def send_json(socket : Socket, data)
        socket.send(data.to_json)
      rescue
      end

      private def send_error(socket : Socket, code : String, message : String)
        send_json(socket, {
          "type"    => "error",
          "code"    => code,
          "message" => message,
        })
      end
    end
  end
end
