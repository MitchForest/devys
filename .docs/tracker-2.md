# Devys - Phase 2: Claude Code Integration Tracker

## Mission: Get Claude Code Working in the Chat UI

### Goal
Create a working custom AI SDK v5 provider that wraps Claude Code CLI, enabling visual chat-based interactions with all Claude Code's powerful agentic capabilities.

## Architecture Summary

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐     ┌──────────────┐
│   Chat UI   │────▶│ Server /chat │────▶│ Custom Provider │────▶│ Claude Code  │
│ (useChat)   │     │  endpoint    │     │ (LanguageModel) │     │     CLI      │
└─────────────┘     └──────────────┘     └─────────────────┘     └──────────────┘
       ▲                                           │                      │
       │                                           │                      │
       └───────────── Stream UI Updates ◀──────────┘                      │
                    (text, tools, etc)                                   │
                                                                        │
┌─────────────┐     ┌──────────────┐                                  │
│   Terminal  │◀────│   Tool       │◀──────── Bash commands ──────────┘
│     UI      │     │  Router      │
└─────────────┘     └──────────────┘
```

## Current Status: CLI Not Found

### The Problem
1. **What Works**: 
   - ✅ AI SDK v5 integration setup correctly
   - ✅ Custom provider implements LanguageModelV2 interface
   - ✅ Message transformation logic (SDKMessage → StreamParts)
   - ✅ Server endpoint using streamText()
   - ✅ Chat UI with useChat hook

2. **What's Broken**:
   - ❌ Claude Code CLI subprocess fails to spawn
   - ❌ Error: `Claude Code executable not found at .../cli.js`
   - ❌ Build process doesn't preserve CLI executable location
   - ❌ Result: Empty streaming responses (0 bytes)

### Root Cause
The `@anthropic-ai/claude-code` package is designed to:
1. Be installed globally or as a dependency
2. Spawn `cli.js` as a subprocess via Node.js
3. Communicate via stdin/stdout JSON messages

When we bundle our app, the build process can't locate `cli.js` because:
- The file path resolution breaks during bundling
- The CLI needs to be accessible as an executable
- The relative path from our dist bundle to node_modules is lost

## Technical Requirements

### 1. Claude Code CLI Integration
- **Must spawn Claude Code as subprocess** (not import as module)
- **Must handle stdin/stdout communication** for message passing
- **Must preserve tool capabilities** (Read, Write, Bash, etc.)
- **Must maintain session state** across messages

### 2. Provider Implementation
- **Implement LanguageModelV2** interface from AI SDK v5
- **Transform SDKMessage types** to LanguageModelV2StreamPart
- **Handle streaming properly** with start/delta/end pattern
- **Manage abort signals** for cancellation

### 3. Message Flow
- **Input**: AI SDK messages → Convert to Claude Code prompt format
- **Output**: Claude Code SDKMessages → Transform to stream parts
- **Tools**: Route tool executions to appropriate UI components

## TODO List

### Phase 2.1: Fix CLI Executable Issue
- [ ] **Option A: Direct Node Modules Reference**
  - Modify `pathToClaudeCodeExecutable` to point to `node_modules/@anthropic-ai/claude-code/cli.js`
  - Ensure path resolution works in both dev and production
  - Test with absolute paths first

- [ ] **Option B: Copy CLI During Build**
  - Add build step to copy `cli.js` to dist folder
  - Update provider to reference copied location
  - Ensure all CLI dependencies are accessible

- [ ] **Option C: Use NPX or Global Install**
  - Check if `claude` is available globally
  - Use `npx @anthropic-ai/claude-code` to spawn
  - Handle cases where it's not installed

### Phase 2.2: Test Basic Chat Flow
- [ ] **Simple Text Response**
  - Send "Hello" and get a response
  - Verify streaming works (text-start, text-delta, text-end)
  - Check session ID is maintained

- [ ] **Error Handling**
  - Test invalid API key
  - Test network failures
  - Test abort/cancellation

### Phase 2.3: Tool Integration
- [ ] **File Operations**
  - Test Read tool - display file contents
  - Test Write tool - show approval dialog
  - Test FileEdit - show diff view

- [ ] **Terminal Operations**
  - Test Bash tool - route to terminal UI
  - Test command output capture
  - Test interactive commands

- [ ] **Advanced Tools**
  - Test Agent spawning
  - Test WebFetch
  - Test search operations

### Phase 2.4: UI Polish
- [ ] **Tool Visualization**
  - Show tool cards during execution
  - Display approval buttons for destructive ops
  - Show progress for long-running tools

- [ ] **Session Management**
  - Save/restore sessions
  - Show session history
  - Handle session continuity

## Success Criteria

1. **Basic Chat Works**: Can send message and receive streamed response
2. **Tools Execute**: File operations and bash commands work with UI feedback
3. **Sessions Persist**: Can continue conversations after restart
4. **No CLI Errors**: Claude Code subprocess spawns successfully

## Key Code Locations

- **Provider**: `/packages/core/src/providers/claude-code-language-model.ts`
- **Server Endpoint**: `/apps/server/src/routes/chat.ts`
- **Chat UI**: `/packages/ui/src/components/chat/chat-interface.tsx`
- **Package with CLI**: `/node_modules/@anthropic-ai/claude-code/`

## Debug Commands

```bash
# Check if CLI exists
ls -la node_modules/@anthropic-ai/claude-code/cli.js

# Test CLI directly
node node_modules/@anthropic-ai/claude-code/cli.js --help

# Check global install
which claude

# Test with npx
npx @anthropic-ai/claude-code --help
```

## References

- Ben Vargas Implementation: https://github.com/ben-vargas/ai-sdk-provider-claude-code
- AI SDK v5 Docs: https://v5.ai-sdk.dev/
- Claude Code SDK: https://docs.anthropic.com/en/docs/claude-code/sdk

---

**Status**: 🔴 Blocked on CLI executable issue
**Next Step**: Implement Phase 2.1 - Fix CLI path resolution
**Priority**: This must work before ANY other features