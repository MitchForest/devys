ultrathink and deep dive this documentation (every link comprehesnively). especially about the claude code typescript sdk, the arguments, the cli options, the input, the output, the multi turn, the agents, slash commands arguments, exit commands, print commands, `--dangerously-skip-permissions` flags, etc

https://docs.anthropic.com/en/docs/claude-code/sdk
https://docs.anthropic.com/en/docs/claude-code/sub-agents
https://docs.anthropic.com/en/docs/claude-code/hooks-guide
https://docs.anthropic.com/en/docs/claude-code/mcp
https://docs.anthropic.com/en/docs/claude-code/cli-reference
https://docs.anthropic.com/en/docs/claude-code/interactive-mode

then deep dive the ai sdk v5 and the very specific inputs, outputs, interfaces, apis, arguments/parameteters, etc (look through every link comprehesnively)

https://v5.ai-sdk.dev/docs/migration-guides/migration-guide-5-0
https://v5.ai-sdk.dev/docs/ai-sdk-ui/chatbot
https://v5.ai-sdk.dev/docs/ai-sdk-ui/transport
https://v5.ai-sdk.dev/docs/ai-sdk-ui/message-metadata
https://v5.ai-sdk.dev/docs/ai-sdk-ui/stream-protocol
https://v5.ai-sdk.dev/docs/ai-sdk-ui/chatbot-tool-usage
https://v5.ai-sdk.dev/docs/reference/ai-sdk-core/stream-text
https://v5.ai-sdk.dev/docs/reference/ai-sdk-ui/use-chat
https://v5.ai-sdk.dev/docs/foundations/agents
https://docs.anthropic.com/en/docs/claude-code/memory
https://docs.anthropic.com/en/docs/claude-code/slash-commands

so far we have built an IDE with codemirror6 and xterm. our goal is to build a cursor like chat ui with the AI chat Command Palett/Panel that utilzies claude code under the hood for its tool calling, context management, etc

this should be a flexible system that can support new sessions, multiple sessions, etc. some workflows may entail the claude code instance understanding natural language input and completing a task. more complex workflows may entail the claude code acting as a thought partner (thinking and discussing), then planning (creating a comprehesnive plan that breaks up a complex assignment into granualr todos assigned to different agents; including QA review type tasks), etc. Each session should create a .md file in a folder (perhaps like .pm for projet management or something) that includes the files created/updtated/deleted), what was done, etc). the user can setup certain hooks or something that require the agents to do certain tasks like typechecking, linting, creating/running tests, and looping until all completion tasks are complete). the main idea for these complex tasks is the user has the planner/orchestrator to communicate with at a higher level while sub agents are spawned to do the granular work and report back to the orchestrator so the orchestrator can keep its context more focused on the bigger picture, and also serve to review what was done or spawn another agent to do so. the user should be able to do TDD or not we need flexibility

claude code is usually a terminal instance so we need to deep dive the typescript sdk and figure out the exact details of how we will integrate it into the ai sdk v5 framework, and how we can support flexible processes. i dont want a guess or estimate of what the implementation of this would be. i want the exact character by character implementation that correctly utilizes the real docs