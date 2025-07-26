# Phase 2 Plan: Simplified Implementation

## What Has Been Done (Current State)

### 1. Claude Code Provider
- Created `packages/core/src/providers/claude-code-language-model.ts`
- Implements AI SDK v5 LanguageModelV2 interface
- Has hooks, streaming, and session support
- **Problem**: Overly complex, trying to do too much

### 2. Project Manager & Sub-Agent Manager
- Created `packages/core/src/services/project-manager.ts` 
- Created `packages/core/src/services/sub-agent-manager.ts`
- **Problem**: Not needed yet, adds unnecessary complexity

### 3. Chat Integration
- Modified `apps/server/src/routes/chat.ts`
- Added agent endpoints
- **Problem**: Too complex, has "workflow" stuff that doesn't belong

### 4. Authentication
- Removed .env files and ANTHROPIC_API_KEY references
- Updated to use Claude Code's `claude setup-token`
- **Status**: This part is correct

## Core Problems to Fix

1. **Desktop app doesn't open** - `bun run dev` starts server but Tauri doesn't launch
2. **Terminal is broken** - Can't type in it
3. **File explorer doesn't work** - Can't open directories/files in editor
4. **Too much complexity** - Workflow, agents, project manager not needed yet

## Simplified Implementation Plan

### Step 1: Get Basic IDE Working
1. **Fix Desktop App Launch**
   - Debug why Tauri isn't starting
   - Ensure `bun run desktop` actually opens the app
   - Test web version separately first

2. **Fix File Explorer**
   - Implement directory listing in sidebar
   - Click file -> opens in CodeMirror editor
   - Basic file tree navigation

3. **Fix Terminal**
   - Make terminal interactive (can type commands)
   - Should work like a normal terminal
   - No connection to chat panel

### Step 2: Add Claude Code to Terminal
1. User should be able to type `claude` in terminal
2. Opens normal Claude Code interactive session
3. Works exactly like terminal Claude Code

### Step 3: Simple Chat Integration
1. **Remove all the complex stuff**:
   - Remove workflow
   - Remove sub-agents
   - Remove project manager
   
2. **Simple implementation**:
   - User types in chat
   - Claude Code responds
   - Tool executions update the editor/terminal
   - That's it!

### Step 4: Advanced Features (Later)
After basic functionality works, then add from `.docs/phase-2/prompt.md`:
- Multi-session support
- Agent orchestration
- Planning capabilities
- TDD workflows
- Hooks for quality gates

## Immediate Actions

1. **Clean up the mess**:
   - Remove workflow route
   - Simplify chat route
   - Remove unnecessary services

2. **Fix core functionality**:
   - Debug Tauri launch
   - Fix terminal input
   - Implement file browser

3. **Test basic flow**:
   - Open app
   - Browse files
   - Edit code
   - Use terminal
   - Try chat (simple version)

## Files to Remove/Simplify

- `/apps/server/src/routes/workflow.ts` - DELETE
- `/packages/core/src/services/project-manager.ts` - REMOVE FOR NOW
- `/packages/core/src/services/sub-agent-manager.ts` - REMOVE FOR NOW
- `/apps/server/src/routes/chat.ts` - SIMPLIFY
- All test files created - DELETE

## Success Criteria

1. **Desktop app opens** when running `bun run dev`
2. **Can browse and open files** in the editor
3. **Terminal works** - can type and run commands
4. **Can run `claude` in terminal** for normal Claude Code
5. **Simple chat works** - type message, get response

Keep it simple. Get the basics working first.