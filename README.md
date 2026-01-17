# Juicy Fruit

A WIP JavaScript based compiler for the Konjac Programming Language and a WebSocket-based debugger interface for the Jelly Virtual Machine.

## Quick Start

```bash
docker compose up
```

## Goal

The current goal is to be able to parse, compile and run the code mentioned below.

```lua
-- An example HTTP server written in Konjac
module Rum.Request
  struct [
    method: String;
    path: String;
    headers: Map(String, String);
  ]
end

module Rum.Response
  struct [
    statusCode: Int64 = 200;
    headers: Map(String, String) = {};
    body: Binary = Binary { };
  ]
  
  export function encode(response : Rum.Response) : Binary
    
    reasonPhrase : String = case response.statusCode
      when 200, do: "OK"
      when 201, do: "Created"
      when 301, do: "Moved Permanently"
      when 400, do: "Bad Request"
      when 404, do: "Not Found"
      when 500, do: "Internal Server Error"
      else do: "Unknown"
    end
    
    statusLine : String = "HTTP/1.1 " + Int64.toString(response.statusCode) + " " + reasonPhrase + "\r\n"

    updatedHeaders : Map(String, String) = if Map.hasKey(response.headers, "Content-Length")
      response.headers
    else
      Map.put(response.headers, "Content-Length", String.fromInt(Binary.length(response.body)))
    end
    
    headersString : String = updatedHeaders
      |> Map.toList()  
      |> Array.map(function(pair : {String, String}) do
        pair.key + ": " + pair.value + "\r\n"
      end)
      |> String.join()
      |> String.concatenate("\r\n\r\n")
      
    statusLine
    |> String.concatenate(headersString)
    |> Binary.fromString()
    |> Binary.concatenate(response.body)
  end
end

module Rum.Context
  struct [
    request: Rum.Request;
    response: Rum.Response;
  ]
end

behaviour Rum.Handler
  abstract function call(handler : Rum.Handler, context : Rum.Context) : Rum.Context
end

module Rum.Server
  struct [
    host: String;
    port: UInt16;
    handlers: Array(Rum.Handler);
  ]

  function handleClient(server : Rum.Server, client : TCP.Client) : Nil
    data : Binary = TCP.receive(client)

    [headerSection, messageBody] = 
      data
      |> Binary.toString()
      |> String.split("\r\n\r\n")

    [startLine, ...unprocessedHeaders]
      headerSection
      |> String.split("\r\n")

    headers =
      unprocessedHeaders 
      |> Array.map(function(header : String) do
        [key, value] = String.split(header)
        
        {key: value}
      end)
      |> Map.zip()
      
    [method, path, "HTTP/1.1"] = startLine |> String.split(" ") |> String.stripSuffix()

    context = 
      Rum.Context { 
        request: Rum.Request { 
          method: method,
          path: path,
          headers: headers 
        }, 
        response: Rum.Response { }
      }

    updatedContext = 
      server.handlers
      |> Array.reduce(function(handler : Rum.Handler, accumulator : Rum.Context) do 
        Rum.handler.call(handler, accumulator)
      end)
      
    encodedResponse = Rum.Response.encode(updatedContext.response)

    TCP.send(client, encodedResponse)
  end

  export function bind(server : Rum.Server) : Rum.Response
    loop do
      client : TCP.Client? = TCP.accept(server.host, server.port)
      
      if client do
        Process.spawn do
          handleClient(server, client)
        end
      else
        Process.killSelf()
      end
    end
  end
end

module Rum.Application
  export function main(arguments : Array(String)) : Nil
    server = Rum.Server { host: "127.0.0.1", port: 8080 as UInt16}

    supervisor = 
      Supervisor {
        strategy: "OneForOne",
        maximumRestarts: 5,
        restartWindow: 10
      }

    process = Process.spawn do
      Rum.Server.bind(server)
    end

    child = Child {
      id: "worker",
      process: process,
      restart: "Transiet",
      maxRestarts: 3,
      restartWindow: 5
    }
    
    Supervisor.addChild(supervisor, child)
  end
end
```

## HTTP Protocol

Connect to `http://localhost:4004/`

## WebSocket Protocol

Connect to `ws://localhost:4004/debugger`

### Commands (Client → Server)

| Command | Parameters | Description |
|---------|------------|-------------|
| `init` | `iterationLimit?` | Initialize VM engine |
| `load` | `instructions` | Load instructions into process |
| `run` | - | Start execution |
| `step` | - | Execute one instruction |
| `continue` | - | Continue to next breakpoint |
| `abort` | - | Stop execution |
| `addBreakpoint` | `conditionType`, `value` | Add breakpoint |
| `removeBreakpoint` | `id` | Remove breakpoint |
| `getState` | - | Get current VM state |
| `listBreakpoints` | - | List all breakpoints |
| `evaluate` | `target`, `limit?` | Evaluate stack/locals |

### Events (Server → Client)

| Event | Description |
|-------|-------------|
| `connected` | Session initialized |
| `initialized` | Engine ready |
| `loaded` | Instructions loaded |
| `running` | Execution started |
| `breakpointHit` | Paused at breakpoint |
| `executionComplete` | Finished execution |
| `executionError` | Runtime error |
| `error` | Command error |

### Instruction Format

```json
{
  "command": "load",
  "instructions": [
    {"code": "PUSH_STRING", "value": {"type": "string", "value": "Hello"}},
    {"code": "PUSH_INTEGER", "value": {"type": "integer", "value": 42}},
    {"code": "PRINT_LINE"}
  ]
}
```

### Value Types

| Type | Example |
|------|---------|
| `string` | `{"type": "string", "value": "hello"}` |
| `integer` | `{"type": "integer", "value": 42}` |
| `float` | `{"type": "float", "value": 3.14}` |
| `symbol` | `{"type": "symbol", "value": "error"}` |
| `uint` | `{"type": "uint", "value": 0}` |
| `bool` | `{"type": "bool", "value": true}` |

### Breakpoint Conditions

| Type | Description |
|------|-------------|
| `counter` | Break at instruction index |
| `minStackDepth` | Break when call stack >= value |
| `maxStackDepth` | Break when call stack <= value |
| `stackSize` | Break when data stack == value |

## Example Session

```javascript
const ws = new WebSocket('ws://localhost:4004/debugger');

ws.onmessage = (e) => console.log(JSON.parse(e.data));

// Initialize
ws.send(JSON.stringify({command: 'init', iterationLimit: 10000}));

// Load program
ws.send(JSON.stringify({
  command: 'load',
  instructions: [
    {code: 'PUSH_STRING', value: {type: 'string', value: 'Hello, World!'}},
    {code: 'PRINT_LINE'},
    {code: 'EXIT_SELF'}
  ]
}));

// Add breakpoint at instruction 1
ws.send(JSON.stringify({
  command: 'addBreakpoint',
  conditionType: 'counter',
  value: 1
}));

// Run
ws.send(JSON.stringify({command: 'run'}));

// When breakpoint hits, step or continue
ws.send(JSON.stringify({command: 'step'}));
```

## Security

The container runs with:
- Non-root user (uid 1000)
- Read-only filesystem
- Dropped capabilities
- Memory limits (512MB)
- CPU limits (1 core)
- Process limits (100 pids)
- No privilege escalation
