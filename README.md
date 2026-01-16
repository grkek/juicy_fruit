# Juicy Fruit - Jelly VM Debugger

WebSocket-based debugger interface for the Jelly Virtual Machine.

## Quick Start

```bash
docker compose up
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
