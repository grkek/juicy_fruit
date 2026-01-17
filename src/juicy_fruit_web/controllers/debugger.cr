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
        property supervisors : Hash(String, VirtualMachine::Supervisor)

        def initialize
          @pending_action = Channel(Action).new(1)
          @breakpoints = {} of String => VirtualMachine::Engine::Debugger::Breakpoint
          @is_running = false
          @supervisors = {} of String => VirtualMachine::Supervisor
        end

        def cleanup
          @pending_action.close rescue nil
          @engine = nil
          @debugger = nil
          @supervisors.clear
        end
      end

      property connections : Hash(Socket, Session) = {} of Socket => Session
      property mutex : Mutex = Mutex.new

      # Handles new WebSocket connection establishment
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

      # Processes incoming WebSocket messages and routes to appropriate handlers
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

      # Responds to WebSocket ping frames
      def on_ping(context : Context, socket : Socket, message : String) : Void
        socket.pong(message)
      end

      # Handles WebSocket pong frames
      def on_pong(context : Context, socket : Socket, message : String) : Void
      end

      # Rejects binary messages as unsupported
      def on_binary(context : Context, socket : Socket, binary : Bytes) : Void
        send_error(socket, "unsupportedFormat", "Binary messages are not supported")
      end

      # Cleans up session resources when WebSocket connection closes
      def on_close(context : Context, socket : Socket, close_code : HTTP::WebSocket::CloseCode | Int?, message : String) : Void
        session = remove_session(socket)
        return unless session

        if session.is_running
          session.pending_action.send(Action::Abort) rescue nil
        end
        session.cleanup
      end

      # Routes commands to their respective handlers
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
        when "stepOver"
          handle_step_over(socket, session)
        when "continue"
          handle_continue(socket, session)
        when "abort"
          handle_abort(socket, session)
        when "addBreakpoint"
          handle_add_breakpoint(socket, session, request)
        when "removeBreakpoint"
          handle_remove_breakpoint(socket, session, request)
        when "enableBreakpoint"
          handle_enable_breakpoint(socket, session, request)
        when "disableBreakpoint"
          handle_disable_breakpoint(socket, session, request)
        when "clearBreakpoints"
          handle_clear_breakpoints(socket, session)
        when "getState"
          handle_get_state(socket, session)
        when "listBreakpoints"
          handle_list_breakpoints(socket, session)
        when "evaluate"
          handle_evaluate(socket, session, request)
        when "getProcessInfo"
          handle_get_process_info(socket, session, request)
        when "listProcesses"
          handle_list_processes(socket, session)
        when "killProcess"
          handle_kill_process(socket, session, request)
        when "sendMessage"
          handle_send_message(socket, session, request)
        when "getMailbox"
          handle_get_mailbox(socket, session, request)
        when "createSupervisor"
          handle_create_supervisor(socket, session, request)
        when "addChild"
          handle_add_child(socket, session, request)
        when "removeChild"
          handle_remove_child(socket, session, request)
        when "restartChild"
          handle_restart_child(socket, session, request)
        when "listSupervisors"
          handle_list_supervisors(socket, session)
        when "getSupervisorInfo"
          handle_get_supervisor_info(socket, session, request)
        when "getSupervisorChildren"
          handle_get_supervisor_children(socket, session, request)
        when "spawnProcess"
          handle_spawn_process(socket, session, request)
        when "spawnLinkedProcess"
          handle_spawn_linked_process(socket, session, request)
        when "spawnMonitoredProcess"
          handle_spawn_monitored_process(socket, session, request)
        when "linkProcesses"
          handle_link_processes(socket, session, request)
        when "unlinkProcesses"
          handle_unlink_processes(socket, session, request)
        when "monitorProcess"
          handle_monitor_process(socket, session, request)
        when "demonitorProcess"
          handle_demonitor_process(socket, session, request)
        when "setTrapExit"
          handle_set_trap_exit(socket, session, request)
        when "exitProcess"
          handle_exit_process(socket, session, request)
        when "registerProcess"
          handle_register_process(socket, session, request)
        when "whereisProcess"
          handle_whereis_process(socket, session, request)
        when "getProcessLinks"
          handle_get_process_links(socket, session, request)
        when "getProcessMonitors"
          handle_get_process_monitors(socket, session, request)
        when "getFaultToleranceStats"
          handle_get_fault_tolerance_stats(socket, session)
        when "getCrashDumps"
          handle_get_crash_dumps(socket, session)
        when "getConfiguration"
          handle_get_configuration(socket, session)
        when "setConfiguration"
          handle_set_configuration(socket, session, request)
        when "getRegisteredProcesses"
          handle_get_registered_processes(socket, session)
        when "inspectStack"
          handle_inspect_stack(socket, session, request)
        when "inspectLocals"
          handle_inspect_locals(socket, session, request)
        when "inspectGlobals"
          handle_inspect_globals(socket, session, request)
        when "setLocal"
          handle_set_local(socket, session, request)
        when "setGlobal"
          handle_set_global(socket, session, request)
        when "getCallStack"
          handle_get_call_stack(socket, session, request)
        when "getInstructions"
          handle_get_instructions(socket, session, request)
        else
          send_error(socket, "unknownCommand", "Unknown command: #{command}")
        end
      end

      # Initializes the VirtualMachine engine and debugger
      private def handle_init(socket : Socket, session : Session, request : JSON::Any) : Void
        if session.engine
          send_error(socket, "alreadyInitialized", "Engine already initialized")
          return
        end

        engine = VirtualMachine::Engine.new

        # Override PRINT_LINE to capture output and send to WebSocket
        engine.on_instruction(VirtualMachine::Code::PRINT_LINE) do |process, instruction|
          process.counter += 1

          if process.stack.empty?
            raise Jelly::VirtualMachine::EmulationException.new("Stack underflow for PRINT_LINE")
          end

          value = process.stack.pop
          output = value.to_s

          # Send to WebSocket
          send_json(socket, {
            "type"           => "stdout",
            "data"           => output,
            "processAddress" => process.address.to_s,
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
              "type"           => "stdout",
              "data"           => output,
              "processAddress" => process.address.to_s,
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

        if max_stack = request["maxStackSize"]?.try(&.as_i64)
          engine.configuration.max_stack_size = max_stack.to_i32
        end

        if max_mailbox = request["maxMailboxSize"]?.try(&.as_i64)
          engine.configuration.max_mailbox_size = max_mailbox.to_i32
        end

        send_json(socket, {
          "type"    => "initialized",
          "message" => "VirtualMachine engine and debugger ready",
        })
      end

      # Loads instructions into the VirtualMachine
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

      # Starts execution of the loaded program
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
            "stats"   => serialize_fault_tolerance_stats(engine),
          })
        end

        send_json(socket, {
          "type"    => "running",
          "message" => "Execution started",
        })
      end

      # Executes a single instruction and pauses
      private def handle_step(socket : Socket, session : Session) : Void
        unless session.is_running
          send_error(socket, "notPaused", "No execution paused at breakpoint")
          return
        end

        session.pending_action.send(Action::Step) rescue nil
      end

      # Executes until the next instruction in the current call frame
      private def handle_step_over(socket : Socket, session : Session) : Void
        unless session.is_running
          send_error(socket, "notPaused", "No execution paused at breakpoint")
          return
        end

        session.pending_action.send(Action::StepOver) rescue nil
      end

      # Continues execution until the next breakpoint
      private def handle_continue(socket : Socket, session : Session) : Void
        unless session.is_running
          send_error(socket, "notPaused", "No execution paused at breakpoint")
          return
        end

        session.pending_action.send(Action::Continue) rescue nil
      end

      # Aborts the current execution
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

      # Adds a new breakpoint with the specified condition
      private def handle_add_breakpoint(socket : Socket, session : Session, request : JSON::Any) : Void
        debugger = session.debugger
        unless debugger
          send_error(socket, "notInitialized", "Debugger not initialized")
          return
        end

        condition_type = request["conditionType"]?.try(&.as_s) || "counter"
        value = request["value"]?.try(&.as_i64) || 0_i64
        ignore_count = request["ignoreCount"]?.try(&.as_i64) || 0_i64

        breakpoint = case condition_type
                     when "counter"
                       debugger.add_breakpoint { |p| p.counter == value }
                     when "minStackDepth"
                       debugger.add_breakpoint { |p| p.call_stack.size >= value }
                     when "maxStackDepth"
                       debugger.add_breakpoint { |p| p.call_stack.size <= value }
                     when "stackSize"
                       debugger.add_breakpoint { |p| p.stack.size == value }
                     when "processAddress"
                       debugger.add_breakpoint { |p| p.address == value.to_u64 }
                     else
                       send_error(socket, "invalidCondition", "Unknown condition type: #{condition_type}")
                       return
                     end

        breakpoint.ignore_count = ignore_count.to_i32
        breakpoint_id = breakpoint.id.to_s
        session.breakpoints[breakpoint_id] = breakpoint

        send_json(socket, {
          "type"          => "breakpointAdded",
          "id"            => breakpoint_id,
          "conditionType" => condition_type,
          "value"         => value,
          "ignoreCount"   => ignore_count,
        })
      end

      # Removes a breakpoint by its identifier
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

      # Enables a disabled breakpoint
      private def handle_enable_breakpoint(socket : Socket, session : Session, request : JSON::Any) : Void
        breakpoint_id = request["id"]?.try(&.as_s)
        unless breakpoint_id
          send_error(socket, "missingId", "Missing breakpoint 'id'")
          return
        end

        if breakpoint = session.breakpoints[breakpoint_id]?
          breakpoint.enable

          send_json(socket, {
            "type"    => "breakpointEnabled",
            "id"      => breakpoint_id,
            "enabled" => true,
          })
        else
          send_error(socket, "notFound", "Breakpoint not found: #{breakpoint_id}")
        end
      end

      # Disables a breakpoint without removing it
      private def handle_disable_breakpoint(socket : Socket, session : Session, request : JSON::Any) : Void
        breakpoint_id = request["id"]?.try(&.as_s)
        unless breakpoint_id
          send_error(socket, "missingId", "Missing breakpoint 'id'")
          return
        end

        if breakpoint = session.breakpoints[breakpoint_id]?
          breakpoint.disable

          send_json(socket, {
            "type"    => "breakpointDisabled",
            "id"      => breakpoint_id,
            "enabled" => false,
          })
        else
          send_error(socket, "notFound", "Breakpoint not found: #{breakpoint_id}")
        end
      end

      # Removes all breakpoints
      private def handle_clear_breakpoints(socket : Socket, session : Session) : Void
        debugger = session.debugger
        unless debugger
          send_error(socket, "notInitialized", "Debugger not initialized")
          return
        end

        debugger.clear_breakpoints
        session.breakpoints.clear

        send_json(socket, {
          "type"    => "breakpointsCleared",
          "message" => "All breakpoints removed",
        })
      end

      # Returns the current state of the VirtualMachine
      private def handle_get_state(socket : Socket, session : Session) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        processes = engine.processes.map do |process|
          {
            "address"        => process.address.to_s,
            "state"          => process.state.to_s,
            "counter"        => process.counter,
            "stackSize"      => process.stack.size,
            "callStackDepth" => process.call_stack.size,
            "mailboxSize"    => process.mailbox.size,
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
          "supervisorCount" => session.supervisors.size,
          "currentProcess"  => current,
        })
      end

      # Lists all registered breakpoints
      private def handle_list_breakpoints(socket : Socket, session : Session) : Void
        breakpoints = session.breakpoints.map do |id, bp|
          {
            "id"          => id,
            "hitCount"    => bp.hit_count,
            "enabled"     => bp.enabled?,
            "ignoreCount" => bp.ignore_count,
          }
        end

        send_json(socket, {
          "type"        => "breakpoints",
          "breakpoints" => breakpoints,
        })
      end

      # Evaluates and returns data from the current process context
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
                 when "globals"
                   process.globals.map { |k, v| {"name" => k, "value" => v.to_s} }
                 when "flags"
                   process.flags.map { |k, v| {"name" => k, "value" => v.to_s} }
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

      # Returns detailed information about a specific process
      private def handle_get_process_info(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        address = address_str.to_u64

        process = engine.processes.find { |p| p.address == address }
        unless process
          send_error(socket, "notFound", "Process not found: #{address}")
          return
        end

        links = engine.process_links.get_links(address)
        monitors = engine.process_links.get_monitors(address)

        send_json(socket, {
          "type"           => "processInfo",
          "address"        => process.address.to_s,
          "state"          => process.state.to_s,
          "counter"        => process.counter,
          "stackSize"      => process.stack.size,
          "callStackDepth" => process.call_stack.size,
          "mailboxSize"    => process.mailbox.size,
          "localsCount"    => process.locals.size,
          "registeredName" => process.registered_name,
          "trapsExit"      => engine.process_links.traps_exit?(address),
          "links"          => links.map(&.to_s),
          "monitors"       => monitors.map { |monitor| {"id" => monitor.id.to_s, "watcher" => monitor.watcher.to_s, "watched" => monitor.watched.to_s} },
          "exitReason"     => process.exit_reason.try(&.to_s),
        })
      end

      # Lists all processes in the VirtualMachine
      private def handle_list_processes(socket : Socket, session : Session) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        processes = engine.processes.map do |process|
          {
            "address"        => process.address.to_s,
            "state"          => process.state.to_s,
            "counter"        => process.counter,
            "stackSize"      => process.stack.size,
            "mailboxSize"    => process.mailbox.size,
            "registeredName" => process.registered_name,
          }
        end

        send_json(socket, {
          "type"      => "processList",
          "processes" => processes,
          "count"     => processes.size,
        })
      end

      # Terminates a process by its address
      private def handle_kill_process(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        address = address_str.to_u64
        process = engine.processes.find { |p| p.address == address && p.state != VirtualMachine::Process::State::DEAD }

        if process
          process.state = VirtualMachine::Process::State::DEAD
          process.exit_reason = VirtualMachine::Process::ExitReason.kill
          engine.fault_handler.handle_exit(process, VirtualMachine::Process::ExitReason.kill)

          send_json(socket, {
            "type"    => "processKilled",
            "address" => address.to_s,
          })
        else
          send_error(socket, "notFound", "Process not found or already dead: #{address}")
        end
      end

      # Sends a message to a process mailbox
      private def handle_send_message(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        message_data = request["message"]?
        unless message_data
          send_error(socket, "missingMessage", "Missing 'message' data")
          return
        end

        address = address_str.to_u64
        process = engine.processes.find { |p| p.address == address && p.state != VirtualMachine::Process::State::DEAD }

        unless process
          send_error(socket, "notFound", "Process not found or dead: #{address}")
          return
        end

        value = parse_value(message_data)
        message = VirtualMachine::Message.new(0_u64, value)

        if process.mailbox.push(message)
          send_json(socket, {
            "type"    => "messageSent",
            "address" => address.to_s,
          })
        else
          send_error(socket, "mailboxFull", "Target mailbox is full")
        end
      end

      # Returns the contents of a process mailbox
      private def handle_get_mailbox(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        address = address_str.to_u64
        process = engine.processes.find { |p| p.address == address }

        unless process
          send_error(socket, "notFound", "Process not found: #{address}")
          return
        end

        limit = request["limit"]?.try(&.as_i64) || 50_i64
        messages = process.mailbox.messages.first(limit.to_i).map do |msg|
          {
            "id"     => msg.id.to_s,
            "sender" => msg.sender.to_s,
            "value"  => msg.value.to_s,
          }
        end

        send_json(socket, {
          "type"       => "mailbox",
          "address"    => address.to_s,
          "messages"   => messages,
          "totalCount" => process.mailbox.size,
        })
      end

      # Creates a new supervisor with the specified configuration
      private def handle_create_supervisor(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        strategy_str = request["strategy"]?.try(&.as_s) || "oneForOne"
        max_restarts = request["maxRestarts"]?.try(&.as_i64) || 3_i64
        restart_window = request["restartWindow"]?.try(&.as_f) || 5.0

        strategy = case strategy_str
                   when "oneForOne"
                     VirtualMachine::Supervisor::RestartStrategy::OneForOne
                   when "oneForAll"
                     VirtualMachine::Supervisor::RestartStrategy::OneForAll
                   when "restForOne"
                     VirtualMachine::Supervisor::RestartStrategy::RestForOne
                   else
                     send_error(socket, "invalidStrategy", "Unknown restart strategy: #{strategy_str}")
                     return
                   end

        supervisor = engine.create_supervisor(
          strategy: strategy,
          max_restarts: max_restarts.to_i32,
          restart_window: restart_window.seconds
        )

        supervisor_id = supervisor.address.to_s
        session.supervisors[supervisor_id] = supervisor

        send_json(socket, {
          "type"          => "supervisorCreated",
          "id"            => supervisor_id,
          "address"       => supervisor.address.to_s,
          "strategy"      => strategy_str,
          "maxRestarts"   => max_restarts,
          "restartWindow" => restart_window,
        })
      end

      # Adds a child specification to a supervisor
      private def handle_add_child(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        supervisor_id = request["supervisorId"]?.try(&.as_s)
        unless supervisor_id
          send_error(socket, "missingSupervisorId", "Missing 'supervisorId'")
          return
        end

        supervisor = session.supervisors[supervisor_id]?
        unless supervisor
          send_error(socket, "notFound", "Supervisor not found: #{supervisor_id}")
          return
        end

        child_id = request["childId"]?.try(&.as_s) || "child_#{Time.utc.to_unix_ms}"
        restart_type_str = request["restartType"]?.try(&.as_s) || "permanent"
        max_restarts = request["maxRestarts"]?.try(&.as_i64) || 3_i64
        restart_window = request["restartWindow"]?.try(&.as_f) || 5.0

        instructions_json = request["instructions"]?.try(&.as_a)
        unless instructions_json
          send_error(socket, "missingInstructions", "Missing 'instructions' array")
          return
        end

        restart_type = case restart_type_str
                       when "permanent"
                         VirtualMachine::Supervisor::RestartType::Permanent
                       when "transient"
                         VirtualMachine::Supervisor::RestartType::Transient
                       when "temporary"
                         VirtualMachine::Supervisor::RestartType::Temporary
                       else
                         send_error(socket, "invalidRestartType", "Unknown restart type: #{restart_type_str}")
                         return
                       end

        begin
          instructions = parse_instructions(instructions_json)

          child_spec = VirtualMachine::Supervisor::Child::Specification.new(
            id: child_id,
            instructions: instructions,
            restart: restart_type,
            max_restarts: max_restarts.to_i32,
            restart_window: restart_window.seconds
          )

          supervisor.add_child(child_spec)

          send_json(socket, {
            "type"          => "childAdded",
            "supervisorId"  => supervisor_id,
            "childId"       => child_id,
            "restartType"   => restart_type_str,
            "maxRestarts"   => max_restarts,
            "restartWindow" => restart_window,
          })
        rescue ex
          send_error(socket, "parseError", "Failed to parse instructions: #{ex.message}")
        end
      end

      # Removes a child from a supervisor
      private def handle_remove_child(socket : Socket, session : Session, request : JSON::Any) : Void
        send_error(socket, "notImplemented", "removeChild is not implemented yet")
      end

      # Restarts a child process under a supervisor
      private def handle_restart_child(socket : Socket, session : Session, request : JSON::Any) : Void
        send_error(socket, "notImplemented", "restartChild is not implemented yet")
      end

      # Lists all supervisors in the session
      private def handle_list_supervisors(socket : Socket, session : Session) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        supervisors = session.supervisors.map do |id, supervisor|
          {
            "id"           => id,
            "address"      => supervisor.address.to_s,
            "strategy"     => supervisor.strategy.to_s,
            "childCount"   => supervisor.children.size,
            "restartCount" => supervisor.restart_histories.map(&.last.restarts.size).sum,
          }
        end

        send_json(socket, {
          "type"        => "supervisorList",
          "supervisors" => supervisors,
          "count"       => supervisors.size,
        })
      end

      # Returns detailed information about a supervisor
      private def handle_get_supervisor_info(socket : Socket, session : Session, request : JSON::Any) : Void
        supervisor_id = request["supervisorId"]?.try(&.as_s)
        unless supervisor_id
          send_error(socket, "missingSupervisorId", "Missing 'supervisorId'")
          return
        end

        supervisor = session.supervisors[supervisor_id]?
        unless supervisor
          send_error(socket, "notFound", "Supervisor not found: #{supervisor_id}")
          return
        end

        send_json(socket, {
          "type"          => "supervisorInfo",
          "id"            => supervisor_id,
          "address"       => supervisor.address.to_s,
          "strategy"      => supervisor.strategy.to_s,
          "maxRestarts"   => supervisor.max_restarts,
          "restartWindow" => supervisor.restart_window.total_seconds,
          "childCount"    => supervisor.children.size,
          "restartCount"  => supervisor.restart_histories.map(&.last.restarts.size).sum,
          "childStatus"   => supervisor.child_status,
        })
      end

      # Returns the list of children under a supervisor
      private def handle_get_supervisor_children(socket : Socket, session : Session, request : JSON::Any) : Void
        supervisor_id = request["supervisorId"]?.try(&.as_s)
        unless supervisor_id
          send_error(socket, "missingSupervisorId", "Missing 'supervisorId'")
          return
        end

        supervisor = session.supervisors[supervisor_id]?
        unless supervisor
          send_error(socket, "notFound", "Supervisor not found: #{supervisor_id}")
          return
        end

        children = supervisor.child_status.map do |child|
          {
            "id"             => child[:id],
            "processAddress" => supervisor.whereis(child[:id]).try(&.to_s),
            "restartType"    => "unknown",
            "restartCount"   => child[:restarts],
          }
        end

        send_json(socket, {
          "type"         => "supervisorChildren",
          "supervisorId" => supervisor_id,
          "children"     => children,
          "count"        => children.size,
        })
      end

      # Spawns a new process with the given instructions
      private def handle_spawn_process(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        instructions_json = request["instructions"]?.try(&.as_a)
        unless instructions_json
          send_error(socket, "missingInstructions", "Missing 'instructions' array")
          return
        end

        begin
          instructions = parse_instructions(instructions_json)
          process = engine.process_manager.create_process(instructions: instructions)
          engine.processes.push(process)

          send_json(socket, {
            "type"    => "processSpawned",
            "address" => process.address.to_s,
          })
        rescue ex
          send_error(socket, "parseError", "Failed to parse instructions: #{ex.message}")
        end
      end

      # Spawns a new process linked to an existing process
      private def handle_spawn_linked_process(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        parent_address_str = request["parentAddress"]?.try(&.as_s)
        unless parent_address_str
          send_error(socket, "missingParentAddress", "Missing 'parentAddress'")
          return
        end

        parent_address = parent_address_str.to_u64
        parent = engine.processes.find { |p| p.address == parent_address && p.state != VirtualMachine::Process::State::DEAD }

        unless parent
          send_error(socket, "notFound", "Parent process not found: #{parent_address}")
          return
        end

        instructions_json = request["instructions"]?.try(&.as_a)
        unless instructions_json
          send_error(socket, "missingInstructions", "Missing 'instructions' array")
          return
        end

        begin
          instructions = parse_instructions(instructions_json)
          child = engine.spawn_link(parent, instructions)

          send_json(socket, {
            "type"          => "linkedProcessSpawned",
            "address"       => child.address.to_s,
            "parentAddress" => parent_address.to_s,
          })
        rescue ex
          send_error(socket, "parseError", "Failed to parse instructions: #{ex.message}")
        end
      end

      # Spawns a new process monitored by an existing process
      private def handle_spawn_monitored_process(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        parent_address_str = request["parentAddress"]?.try(&.as_s)
        unless parent_address_str
          send_error(socket, "missingParentAddress", "Missing 'parentAddress'")
          return
        end

        parent_address = parent_address_str.to_u64
        parent = engine.processes.find { |p| p.address == parent_address && p.state != VirtualMachine::Process::State::DEAD }

        unless parent
          send_error(socket, "notFound", "Parent process not found: #{parent_address}")
          return
        end

        instructions_json = request["instructions"]?.try(&.as_a)
        unless instructions_json
          send_error(socket, "missingInstructions", "Missing 'instructions' array")
          return
        end

        begin
          instructions = parse_instructions(instructions_json)
          child, ref = engine.spawn_monitor(parent, instructions)

          send_json(socket, {
            "type"          => "monitoredProcessSpawned",
            "address"       => child.address.to_s,
            "parentAddress" => parent_address.to_s,
            "monitorRef"    => ref.id.to_s,
          })
        rescue ex
          send_error(socket, "parseError", "Failed to parse instructions: #{ex.message}")
        end
      end

      # Creates a bidirectional link between two processes
      private def handle_link_processes(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address1_str = request["address1"]?.try(&.as_s)
        address2_str = request["address2"]?.try(&.as_s)

        unless address1_str && address2_str
          send_error(socket, "missingAddresses", "Missing 'address1' or 'address2'")
          return
        end

        address1 = address1_str.to_u64
        address2 = address2_str.to_u64

        process1 = engine.processes.find { |p| p.address == address1 && p.state != VirtualMachine::Process::State::DEAD }
        process2 = engine.processes.find { |p| p.address == address2 && p.state != VirtualMachine::Process::State::DEAD }

        unless process1 && process2
          send_error(socket, "notFound", "One or both processes not found or dead")
          return
        end

        engine.process_links.link(address1, address2)

        send_json(socket, {
          "type"     => "processesLinked",
          "address1" => address1.to_s,
          "address2" => address2.to_s,
        })
      end

      # Removes a link between two processes
      private def handle_unlink_processes(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address1_str = request["address1"]?.try(&.as_s)
        address2_str = request["address2"]?.try(&.as_s)

        unless address1_str && address2_str
          send_error(socket, "missingAddresses", "Missing 'address1' or 'address2'")
          return
        end

        address1 = address1_str.to_u64
        address2 = address2_str.to_u64

        result = engine.process_links.unlink(address1, address2)

        send_json(socket, {
          "type"     => "processesUnlinked",
          "address1" => address1.to_s,
          "address2" => address2.to_s,
          "success"  => result,
        })
      end

      # Creates a monitor from one process to another
      private def handle_monitor_process(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        monitor_address_str = request["monitorAddress"]?.try(&.as_s)
        target_address_str = request["targetAddress"]?.try(&.as_s)

        unless monitor_address_str && target_address_str
          send_error(socket, "missingAddresses", "Missing 'monitorAddress' or 'targetAddress'")
          return
        end

        monitor_address = monitor_address_str.to_u64
        target_address = target_address_str.to_u64

        ref = engine.process_links.monitor(monitor_address, target_address)

        send_json(socket, {
          "type"           => "monitorCreated",
          "monitorAddress" => monitor_address.to_s,
          "targetAddress"  => target_address.to_s,
          "monitorRef"     => ref.id.to_s,
        })
      end

      # Removes a monitor
      private def handle_demonitor_process(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        monitor_address_str = request["monitorAddress"]?.try(&.as_s)
        ref_id_str = request["monitorRef"]?.try(&.as_s)

        unless monitor_address_str && ref_id_str
          send_error(socket, "missingParams", "Missing 'monitorAddress' or 'monitorRef'")
          return
        end

        monitor_address = monitor_address_str.to_u64
        ref_id = ref_id_str.to_u64

        monitors = engine.process_links.get_monitors(monitor_address)
        ref = monitors.find { |r| r.id == ref_id }

        if ref
          result = engine.process_links.demonitor(ref)

          send_json(socket, {
            "type"       => "monitorRemoved",
            "monitorRef" => ref_id.to_s,
            "success"    => result,
          })
        else
          send_error(socket, "notFound", "Monitor reference not found: #{ref_id}")
        end
      end

      # Enables or disables exit trapping for a process
      private def handle_set_trap_exit(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        enable = request["enable"]?.try(&.as_bool) || false
        address = address_str.to_u64

        old_value = engine.process_links.traps_exit?(address)
        engine.process_links.trap_exit(address, enable)

        send_json(socket, {
          "type"     => "trapExitSet",
          "address"  => address.to_s,
          "enabled"  => enable,
          "previous" => old_value,
        })
      end

      # Sends an exit signal to a process
      private def handle_exit_process(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        reason = request["reason"]?.try(&.as_s) || "normal"
        address = address_str.to_u64

        engine.exit_process(address, reason)

        send_json(socket, {
          "type"    => "exitSignalSent",
          "address" => address.to_s,
          "reason"  => reason,
        })
      end

      # Registers a process with a name
      private def handle_register_process(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        name = request["name"]?.try(&.as_s)

        unless address_str && name
          send_error(socket, "missingParams", "Missing 'address' or 'name'")
          return
        end

        address = address_str.to_u64
        process = engine.processes.find { |p| p.address == address }

        unless process
          send_error(socket, "notFound", "Process not found: #{address}")
          return
        end

        if engine.process_registry.register(name, address)
          process.registered_name = name

          send_json(socket, {
            "type"    => "processRegistered",
            "address" => address.to_s,
            "name"    => name,
          })
        else
          send_error(socket, "registrationFailed", "Name already taken: #{name}")
        end
      end

      # Looks up a process by its registered name
      private def handle_whereis_process(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        name = request["name"]?.try(&.as_s)
        unless name
          send_error(socket, "missingName", "Missing 'name'")
          return
        end

        if address = engine.process_registry.lookup(name)
          send_json(socket, {
            "type"    => "processFound",
            "name"    => name,
            "address" => address.to_s,
          })
        else
          send_json(socket, {
            "type"    => "processNotFound",
            "name"    => name,
            "address" => nil,
          })
        end
      end

      # Returns the links for a specific process
      private def handle_get_process_links(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        address = address_str.to_u64
        links = engine.process_links.get_links(address)

        send_json(socket, {
          "type"    => "processLinks",
          "address" => address.to_s,
          "links"   => links.map(&.to_s),
          "count"   => links.size,
        })
      end

      # Returns the monitors for a specific process
      private def handle_get_process_monitors(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        address = address_str.to_u64
        monitors = engine.process_links.get_monitors(address)

        send_json(socket, {
          "type"     => "processMonitors",
          "address"  => address.to_s,
          "monitors" => monitors.map { |monitor| {"id" => monitor.id.to_s, "watcher" => monitor.watcher.to_s, "watched" => monitor.watched.to_s} },
          "count"    => monitors.size,
        })
      end

      # Returns fault tolerance statistics for the engine
      private def handle_get_fault_tolerance_stats(socket : Socket, session : Session) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        send_json(socket, {
          "type"  => "faultToleranceStats",
          "stats" => serialize_fault_tolerance_stats(engine),
        })
      end

      # Returns stored crash dumps
      private def handle_get_crash_dumps(socket : Socket, session : Session) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        dumps = engine.crash_dump_storage.all.map do |dump|
          {
            "processAddress" => dump.process_address.to_s,
            "timestamp"      => dump.timestamp.to_s,
            "reason"         => dump.exit_reason.type.to_s,
            "stackTrace"     => dump.stack_trace.map(&.inspect),
          }
        end

        send_json(socket, {
          "type"       => "crashDumps",
          "dumps"      => dumps,
          "totalCount" => dumps.size,
        })
      end

      # Returns the current engine configuration
      private def handle_get_configuration(socket : Socket, session : Session) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        config = engine.configuration

        send_json(socket, {
          "type"          => "configuration",
          "configuration" => {
            "iterationLimit"               => config.iteration_limit,
            "maxStackSize"                 => config.max_stack_size,
            "maxMailboxSize"               => config.max_mailbox_size,
            "executionDelay"               => config.execution_delay.total_seconds,
            "deadlockDetection"            => config.deadlock_detection,
            "autoReactivateProcesses"      => config.auto_reactivate_processes,
            "enableMessageAcknowledgments" => config.enable_message_acknowledgments,
          },
        })
      end

      # Updates the engine configuration
      private def handle_set_configuration(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        config = engine.configuration

        if value = request["iterationLimit"]?.try(&.as_i64)
          config.iteration_limit = value.to_i32
        end

        if value = request["maxStackSize"]?.try(&.as_i64)
          config.max_stack_size = value.to_i32
        end

        if value = request["maxMailboxSize"]?.try(&.as_i64)
          config.max_mailbox_size = value.to_i32
        end

        if value = request["executionDelay"]?.try(&.as_f)
          config.execution_delay = value.seconds
        end

        if value = request["deadlockDetection"]?.try(&.as_bool)
          config.deadlock_detection = value
        end

        if value = request["autoReactivateProcesses"]?.try(&.as_bool)
          config.auto_reactivate_processes = value
        end

        if value = request["enableMessageAcknowledgments"]?.try(&.as_bool)
          config.enable_message_acknowledgments = value
        end

        send_json(socket, {
          "type"    => "configurationUpdated",
          "message" => "Configuration updated successfully",
        })
      end

      # Returns all registered process names and addresses
      private def handle_get_registered_processes(socket : Socket, session : Session) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        registered = engine.processes
          .select { |p| p.registered_name }
          .map { |p| {"name" => p.registered_name, "address" => p.address.to_s} }

        send_json(socket, {
          "type"      => "registeredProcesses",
          "processes" => registered,
          "count"     => registered.size,
        })
      end

      # Returns the stack contents for a specific process
      private def handle_inspect_stack(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        address = address_str.to_u64
        process = engine.processes.find { |p| p.address == address }

        unless process
          send_error(socket, "notFound", "Process not found: #{address}")
          return
        end

        limit = request["limit"]?.try(&.as_i64) || 100_i64
        offset = request["offset"]?.try(&.as_i64) || 0_i64

        stack_slice = process.stack.reverse.skip(offset.to_i).first(limit.to_i)
        stack_items = stack_slice.map_with_index do |value, idx|
          {
            "index" => process.stack.size - 1 - offset.to_i - idx,
            "value" => value.to_s,
            "type"  => value.type,
          }
        end

        send_json(socket, {
          "type"      => "stackInspection",
          "address"   => address.to_s,
          "items"     => stack_items,
          "totalSize" => process.stack.size,
          "offset"    => offset,
          "limit"     => limit,
        })
      end

      # Returns the local variables for a specific process
      private def handle_inspect_locals(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        address = address_str.to_u64
        process = engine.processes.find { |p| p.address == address }

        unless process
          send_error(socket, "notFound", "Process not found: #{address}")
          return
        end

        locals = process.locals.map_with_index do |value, idx|
          {
            "index" => idx,
            "value" => value.to_s,
            "type"  => value.type,
          }
        end

        send_json(socket, {
          "type"    => "localsInspection",
          "address" => address.to_s,
          "locals"  => locals,
          "count"   => locals.size,
        })
      end

      # Returns the global variables for a specific process
      private def handle_inspect_globals(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        address = address_str.to_u64
        process = engine.processes.find { |p| p.address == address }

        unless process
          send_error(socket, "notFound", "Process not found: #{address}")
          return
        end

        globals = process.globals.map do |name, value|
          {
            "name"  => name,
            "value" => value.to_s,
            "type"  => value.type,
          }
        end

        send_json(socket, {
          "type"    => "globalsInspection",
          "address" => address.to_s,
          "globals" => globals,
          "count"   => globals.size,
        })
      end

      # Sets a local variable value for the current paused process
      private def handle_set_local(socket : Socket, session : Session, request : JSON::Any) : Void
        process = session.current_process
        unless process
          send_error(socket, "notPaused", "No process paused for modification")
          return
        end

        index = request["index"]?.try(&.as_i64)
        unless index
          send_error(socket, "missingIndex", "Missing 'index'")
          return
        end

        value_data = request["value"]?
        unless value_data
          send_error(socket, "missingValue", "Missing 'value'")
          return
        end

        value = parse_value(value_data)

        while process.locals.size <= index
          process.locals.push(VirtualMachine::Value.new)
        end

        process.locals[index.to_i] = value

        send_json(socket, {
          "type"  => "localSet",
          "index" => index,
          "value" => value.to_s,
        })
      end

      # Sets a global variable value for the current paused process
      private def handle_set_global(socket : Socket, session : Session, request : JSON::Any) : Void
        process = session.current_process
        unless process
          send_error(socket, "notPaused", "No process paused for modification")
          return
        end

        name = request["name"]?.try(&.as_s)
        unless name
          send_error(socket, "missingName", "Missing 'name'")
          return
        end

        value_data = request["value"]?
        unless value_data
          send_error(socket, "missingValue", "Missing 'value'")
          return
        end

        value = parse_value(value_data)
        process.globals[name] = value

        send_json(socket, {
          "type"  => "globalSet",
          "name"  => name,
          "value" => value.to_s,
        })
      end

      # Returns the call stack for a specific process
      private def handle_get_call_stack(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        address = address_str.to_u64
        process = engine.processes.find { |p| p.address == address }

        unless process
          send_error(socket, "notFound", "Process not found: #{address}")
          return
        end

        frames = process.call_stack.map_with_index do |return_addr, idx|
          {
            "index"         => idx,
            "returnAddress" => return_addr,
          }
        end

        send_json(socket, {
          "type"         => "callStack",
          "address"      => address.to_s,
          "frames"       => frames,
          "currentFrame" => process.frame_pointer,
          "depth"        => frames.size,
        })
      end

      # Returns the instructions for a specific process
      private def handle_get_instructions(socket : Socket, session : Session, request : JSON::Any) : Void
        engine = session.engine
        unless engine
          send_error(socket, "notInitialized", "Engine not initialized")
          return
        end

        address_str = request["address"]?.try(&.as_s)
        unless address_str
          send_error(socket, "missingAddress", "Missing process 'address'")
          return
        end

        address = address_str.to_u64
        process = engine.processes.find { |p| p.address == address }

        unless process
          send_error(socket, "notFound", "Process not found: #{address}")
          return
        end

        start_idx = request["start"]?.try(&.as_i64) || 0_i64
        count = request["count"]?.try(&.as_i64) || 50_i64

        instructions = process.instructions.skip(start_idx.to_i).first(count.to_i).map_with_index do |instr, idx|
          {
            "index"   => start_idx + idx,
            "code"    => instr.code.to_s,
            "value"   => instr.value.to_s,
            "current" => (start_idx + idx) == process.counter,
          }
        end

        send_json(socket, {
          "type"         => "instructions",
          "address"      => address.to_s,
          "instructions" => instructions,
          "counter"      => process.counter,
          "totalCount"   => process.instructions.size,
        })
      end

      # Serializes process state for transmission
      private def serialize_process_state(process, instruction)
        {
          "address"        => process.address.to_s,
          "counter"        => process.counter,
          "state"          => process.state.to_s,
          "callStackDepth" => process.call_stack.size,
          "instruction"    => instruction.try(&.code.to_s) || "none",
          "stack"          => process.stack.reverse.first(10).reverse.map(&.to_s),
          "locals"         => process.locals.map(&.to_s),
          "registeredName" => process.registered_name,
        }
      end

      # Serializes fault tolerance statistics
      private def serialize_fault_tolerance_stats(engine)
        stats = engine.fault_tolerance_statistics
        {
          "links"       => stats[:links],
          "monitors"    => stats[:monitors],
          "trapping"    => stats[:trapping],
          "supervisors" => stats[:supervisors],
          "crashDumps"  => stats[:crash_dumps],
        }
      end

      # Parses a JSON array of instructions into VirtualMachine instructions
      private def parse_instructions(json_array : Array(JSON::Any)) : Array(VirtualMachine::Instruction)
        json_array.map do |item|
          code_str = item["code"]?.try(&.as_s)
          raise "Missing 'code' in instruction" unless code_str

          code = VirtualMachine::Code.parse(code_str)
          value = parse_value(item["value"]?)

          VirtualMachine::Instruction.new(code, value)
        end
      end

      # Parses a JSON value into a VirtualMachine Value
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
        when "null"
          VirtualMachine::Value.new(nil)
        else
          VirtualMachine::Value.new(nil)
        end
      end

      # Retrieves a session for a socket with thread safety
      private def get_session(socket : Socket) : Session?
        mutex.synchronize do
          connections[socket]?
        end
      end

      # Removes and returns a session for a socket with thread safety
      private def remove_session(socket : Socket) : Session?
        mutex.synchronize do
          connections.delete(socket)
        end
      end

      # Sends a JSON message through the WebSocket
      private def send_json(socket : Socket, data)
        socket.send(data.to_json)
      rescue
      end

      # Sends an error message through the WebSocket
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
