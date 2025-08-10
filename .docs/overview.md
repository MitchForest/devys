Phase 1 (✅ Complete): Dual-plane architecture establishing sub-50ms keystroke latency via Rust PTY sidecar + Bun control plane

Phase 2 (Current): Context intelligence layer with Merkle-tree caching for instant, token-optimized AI context generation

----------------------


Phase 3 (Proposed): Multi-model AI orchestration via claude-code-router with agent specialization (o3, editor→Claude, reviewer→Gemini)

Claude Code, CC Router, Agents, Hooks, Slash Commands, etc

Plan Mode (where new chats start) + Edit Mode + (optional) Review Mode

The prompt RepoPrompt generates typically includes:

Plan Mode:
System instructions: From your active stored prompts
Your specific query: From the Instructions text area
File map: A structured outline of the selected files
File contents: The actual code from selected files
Code Maps: If enabled, structured summaries of code definitions

Edit Mode:
System instructions: From your active stored prompts
Your specific query: From the Planner Agent
File map: A structured outline of the selected files (from Planner Agent)
Code Maps: If enabled, structured summaries of code definitions
Plan Doc: detailed checklist plan from Plan Agent (including definition of comoplete/success)

(optional) Review Mode:
Plan Doc:
List of files editied/modified
Definition of Complete/Success

(optional) Grunt Mode:

Here's how Pro Mode functions:

Planning Model: This is the primary model you select in your chat session. It handles the overall planning and high-level decisions, such as creating new files, deleting files, and structuring complex edits. It breaks down larger tasks into concise, actionable changes for other models to execute efficiently.

Edit Models: These models receive specific file edits determined by the planning model. They work in parallel, enabling faster responses, reducing token usage, and controlling costs. Edit tasks are automatically routed to models based on file complexity and size.


1. Stored Prompts Management
The system needs to store and manage reusable prompt templates:

System prompts for different agents (planner, editor, reviewer)
Task-specific prompts
Variable interpolation in prompts

2. Agent-Specific Context Assembly
Different agents need different context formats:

Planner: Full context with all file contents
Editor: Code maps + specific files from plan
Reviewer: Diffs + surrounding context

3. Context Composition Pipeline
The final assembly that combines:
System Instructions (stored prompts)
↓
User Query (specific task)
↓
File Map (structure overview)
↓
Code Maps (symbol summaries)
↓
Selected File Contents (optimized)
4. Integration Points

How this connects to claude-code CLI
How agents consume the context
Router integration for model selection




----------------------




Phase 4 (Proposed): "Grunt mode" integration for free/local models handling grunt work (git ops, tests, docs, linting)
-AI Context Builder (instead of manually selecting files) for planner

Phase 5 (Proposed): Platform-specific frontends (Tauri desktop, iOS PWA, Android Termux/PWA)

Phase 6 (Proposed): Firecracker microVMs for secure isolated execution environments

Phase 7 (Proposed): Monetization layer with self-hosted vs managed tiers ($19/mo)
-Use our hosted free models for Grunt so its truly free/unlimited
-Use our microVMs
-You bring your CC
-You bring your api keys and/or open router

Phase 8 (Proposed): Production deployment, monitoring, and scaling infrastructure

