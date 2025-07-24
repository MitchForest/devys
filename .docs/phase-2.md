# Claude Code IDE - Phase 2 Implementation Plan

## Overview
Phase 2 transforms the basic IDE into a sophisticated multi-agent development environment, leveraging AI SDK v5's advanced patterns and Claude Code SDK's full capabilities. This phase focuses on agent orchestration, workflow customization, and developer experience enhancements.

## Key Technology Integrations

### AI SDK v5 Core Types & Patterns
```typescript
import { 
  generateText, 
  streamText, 
  tool, 
  stepCountIs,
  ToolCall,
  ToolResult,
  ToolSet,
  ToolCallUnion,
  ToolResultUnion,
  ModelMessage,
  AssistantMessage,
  TextBlock,
  experimental_createMCPClient as createMCPClient,
  MCPClient,
  stopWhen
} from 'ai';
import { z } from 'zod';
```

### Claude Code SDK Integration
```typescript
import { 
  query as claudeQuery, 
  ClaudeCodeOptions,
  MessageType,
  AssistantMessage as ClaudeAssistantMessage,
  ToolUseBlock,
  ToolResultBlock
} from '@anthropic-ai/claude-code';
```

## Phase 2 Architecture Enhancements

### 1. Multi-Agent System Architecture

#### Agent Type Definitions
```typescript
// packages/core/src/agents/types.ts
import { ToolSet, ModelMessage, generateText } from 'ai';
import { z } from 'zod';

export interface AgentCapabilities {
  tools: ToolSet;
  maxSteps: number;
  stopConditions?: typeof stopWhen;
}

export interface AgentContext {
  projectPath: string;
  memory: MemoryStore;
  messages: ModelMessage[];
  sharedState: Map<string, unknown>;
}

export abstract class BaseAgent {
  constructor(
    protected name: string,
    protected systemPrompt: string,
    protected capabilities: AgentCapabilities
  ) {}

  abstract async execute(
    task: AgentTask,
    context: AgentContext
  ): Promise<AgentResult>;
}

// Coordinator Agent using AI SDK v5
export class CoordinatorAgent extends BaseAgent {
  private orchestrationTools = {
    delegateTask: tool({
      description: 'Delegate a task to a specialized agent',
      parameters: z.object({
        agentType: z.enum(['planner', 'executor', 'verifier', 'analyzer']),
        task: z.string(),
        context: z.record(z.unknown())
      }),
      execute: async ({ agentType, task, context }) => {
        // Delegate to appropriate agent
        return this.agentRegistry.dispatch(agentType, task, context);
      }
    }),
    
    aggregateResults: tool({
      description: 'Aggregate results from multiple agents',
      parameters: z.object({
        results: z.array(z.any()),
        aggregationType: z.enum(['merge', 'summarize', 'validate'])
      }),
      execute: async ({ results, aggregationType }) => {
        // Aggregate based on type
        return this.aggregator[aggregationType](results);
      }
    })
  };

  async execute(task: AgentTask, context: AgentContext): Promise<AgentResult> {
    const { steps } = await generateText({
      model: this.model,
      system: this.systemPrompt,
      messages: context.messages,
      tools: { ...this.orchestrationTools, ...this.capabilities.tools },
      maxSteps: 10,
      stopWhen: stepCountIs(10),
      onStepFinish: async ({ text, toolCalls, toolResults }) => {
        // Track orchestration progress
        await this.updateProgress(task.id, { text, toolCalls, toolResults });
      }
    });

    return this.processSteps(steps);
  }
}
```

#### Specialized Agent Implementations
```typescript
// Planner Agent - Analyzes and creates implementation plans
export class PlannerAgent extends BaseAgent {
  constructor() {
    super('planner', PLANNER_SYSTEM_PROMPT, {
      tools: {
        analyzeCodebase: tool({
          description: 'Deep analysis of codebase structure',
          parameters: z.object({
            focusAreas: z.array(z.string()),
            depth: z.enum(['shallow', 'medium', 'deep'])
          }),
          execute: async ({ focusAreas, depth }) => {
            // Use Claude Code SDK for analysis
            const analysis = await this.performAnalysis(focusAreas, depth);
            return analysis;
          }
        }),
        
        createImplementationPlan: tool({
          description: 'Create detailed implementation plan',
          parameters: z.object({
            requirements: z.string(),
            constraints: z.array(z.string()),
            analysisResults: z.any()
          }),
          execute: async (params) => {
            return this.generatePlan(params);
          }
        })
      },
      maxSteps: 5
    });
  }
}

// Executor Agent - Implements changes
export class ExecutorAgent extends BaseAgent {
  constructor(specialization: 'frontend' | 'backend' | 'database' | 'testing') {
    super(`executor-${specialization}`, EXECUTOR_PROMPTS[specialization], {
      tools: {
        modifyFile: tool({
          description: 'Modify file contents',
          parameters: z.object({
            path: z.string(),
            changes: z.array(z.object({
              type: z.enum(['add', 'modify', 'delete']),
              location: z.any(),
              content: z.string()
            }))
          }),
          execute: async ({ path, changes }) => {
            // Apply changes with approval queue
            return this.applyChanges(path, changes);
          }
        }),
        
        runCommand: tool({
          description: 'Execute shell command',
          parameters: z.object({
            command: z.string(),
            cwd: z.string().optional()
          }),
          execute: async ({ command, cwd }) => {
            // Execute with proper sandboxing
            return this.executeCommand(command, cwd);
          }
        })
      },
      maxSteps: 15
    });
  }
}
```

### 2. Advanced Workflow Engine

#### Workflow Patterns from AI SDK v5
```typescript
// packages/core/src/workflows/engine.ts
import { generateText, streamText, tool, stopWhen } from 'ai';

export class WorkflowEngine {
  private patterns = {
    // Sequential Processing Pattern
    sequential: async (steps: WorkflowStep[]) => {
      let context = {};
      for (const step of steps) {
        const result = await this.executeStep(step, context);
        context = { ...context, ...result };
      }
      return context;
    },

    // Parallel Processing Pattern
    parallel: async (steps: WorkflowStep[]) => {
      const results = await Promise.all(
        steps.map(step => this.executeStep(step, {}))
      );
      return this.mergeResults(results);
    },

    // Routing Pattern
    routing: async (condition: string, branches: WorkflowBranch[]) => {
      const { object: decision } = await generateObject({
        model: this.model,
        schema: z.object({
          selectedBranch: z.string(),
          reasoning: z.string()
        }),
        prompt: `Evaluate condition: ${condition}\nSelect branch from: ${branches.map(b => b.name)}`
      });
      
      const branch = branches.find(b => b.name === decision.selectedBranch);
      return this.executeWorkflow(branch.workflow);
    },

    // Evaluator-Optimizer Pattern
    evaluatorOptimizer: async (task: Task, maxIterations = 3) => {
      let result = await this.executeTask(task);
      let iteration = 0;

      while (iteration < maxIterations) {
        const { object: evaluation } = await generateObject({
          model: this.evaluatorModel,
          schema: z.object({
            score: z.number().min(0).max(10),
            issues: z.array(z.string()),
            suggestions: z.array(z.string()),
            acceptable: z.boolean()
          }),
          prompt: `Evaluate this result: ${JSON.stringify(result)}`
        });

        if (evaluation.acceptable || evaluation.score >= 8) break;

        // Optimize based on evaluation
        result = await this.optimizeResult(result, evaluation);
        iteration++;
      }

      return result;
    }
  };
}
```

#### Custom Workflow DSL
```typescript
// Workflow definition with Zod validation
const WorkflowSchema = z.object({
  version: z.string(),
  name: z.string(),
  description: z.string(),
  triggers: z.array(z.enum(['manual', 'file-change', 'git-hook', 'schedule'])),
  
  agents: z.record(z.object({
    type: z.string(),
    config: z.record(z.any()),
    capabilities: z.array(z.string())
  })),
  
  phases: z.array(z.object({
    name: z.string(),
    pattern: z.enum(['sequential', 'parallel', 'routing', 'evaluator-optimizer']),
    agents: z.array(z.string()),
    
    approval: z.object({
      required: z.boolean(),
      type: z.enum(['manual', 'auto', 'conditional'])
    }).optional(),
    
    onSuccess: z.string().optional(),
    onFailure: z.string().optional()
  }))
});

// Example workflow configuration
const complexWorkflow = {
  version: "2.0",
  name: "feature-implementation",
  description: "Multi-agent feature implementation workflow",
  triggers: ["manual"],
  
  agents: {
    coordinator: {
      type: "coordinator",
      config: { model: "claude-opus-4" },
      capabilities: ["orchestrate", "aggregate"]
    },
    planner: {
      type: "planner",
      config: { analysisDepth: "deep" },
      capabilities: ["analyze", "plan"]
    },
    frontendDev: {
      type: "executor",
      config: { specialization: "frontend" },
      capabilities: ["modify-files", "run-commands"]
    },
    backendDev: {
      type: "executor",
      config: { specialization: "backend" },
      capabilities: ["modify-files", "run-commands"]
    },
    tester: {
      type: "verifier",
      config: { testTypes: ["unit", "integration"] },
      capabilities: ["run-tests", "analyze-coverage"]
    }
  },
  
  phases: [
    {
      name: "analysis",
      pattern: "sequential",
      agents: ["coordinator", "planner"],
      approval: { required: true, type: "manual" }
    },
    {
      name: "implementation",
      pattern: "parallel",
      agents: ["frontendDev", "backendDev"],
      approval: { required: false, type: "auto" }
    },
    {
      name: "verification",
      pattern: "evaluator-optimizer",
      agents: ["tester"],
      onSuccess: "deploy",
      onFailure: "rollback"
    }
  ]
};
```

### 3. MCP Integration with AI SDK v5

```typescript
// packages/core/src/mcp/integration.ts
import { experimental_createMCPClient as createMCPClient, MCPClient } from 'ai';
import { z } from 'zod';

export class MCPManager {
  private clients: Map<string, MCPClient> = new Map();
  
  async loadFromConfig(configPath: string) {
    const config = await this.readMCPConfig(configPath);
    
    for (const [name, serverConfig] of Object.entries(config.servers)) {
      const client = await this.createClient(name, serverConfig);
      this.clients.set(name, client);
    }
  }

  private async createClient(name: string, config: MCPServerConfig) {
    if (config.type === 'stdio') {
      const { Experimental_StdioMCPTransport } = await import('ai/mcp-stdio');
      return createMCPClient({
        transport: new Experimental_StdioMCPTransport({
          command: config.command,
          args: config.args,
          env: config.env
        })
      });
    } else if (config.type === 'sse') {
      return createMCPClient({
        transport: {
          type: 'sse',
          url: config.url,
          headers: config.headers
        }
      });
    }
  }

  async getToolsForAgent(agentType: string): Promise<ToolSet> {
    const tools: ToolSet = {};
    
    for (const [serverName, client] of this.clients) {
      const serverTools = await client.tools({
        schemas: this.getSchemaForAgent(agentType, serverName)
      });
      
      Object.assign(tools, serverTools);
    }
    
    return tools;
  }
}
```

### 4. Enhanced Memory System

```typescript
// packages/core/src/memory/enhanced.ts
export class EnhancedMemorySystem {
  private workflowMemory = new WorkflowMemory();
  private projectContext = new ProjectContextManager();
  private semanticIndex = new SemanticIndex();
  
  async recordWorkflowExecution(workflow: ExecutedWorkflow) {
    // Extract key decisions and patterns
    const summary = await this.summarizeWorkflow(workflow);
    
    // Store in structured format
    await this.workflowMemory.store({
      id: workflow.id,
      timestamp: new Date(),
      request: workflow.initialRequest,
      
      phases: workflow.phases.map(phase => ({
        name: phase.name,
        agents: phase.agents,
        decisions: phase.decisions,
        outcomes: phase.outcomes
      })),
      
      insights: {
        successPatterns: summary.successPatterns,
        failures: summary.failures,
        optimizations: summary.suggestedOptimizations
      },
      
      artifacts: {
        filesModified: workflow.filesModified,
        testsAdded: workflow.testsAdded,
        dependencies: workflow.dependenciesChanged
      }
    });
    
    // Update semantic index for future retrieval
    await this.semanticIndex.index(summary);
  }
  
  async getRelevantContext(query: string): Promise<Context[]> {
    // Semantic search across all memory stores
    const relevantWorkflows = await this.semanticIndex.search(query, { limit: 5 });
    const projectPatterns = await this.projectContext.getPatterns();
    
    return this.mergeContexts(relevantWorkflows, projectPatterns);
  }
}
```

### 5. Git Worktree Integration

```typescript
// packages/core/src/git/worktree.ts
export class WorktreeManager {
  async createCheckpoint(name: string, description: string) {
    const checkpointId = `checkpoint-${Date.now()}`;
    
    // Create worktree for isolation
    await this.git.worktree.add({
      path: `.worktrees/${checkpointId}`,
      commitish: 'HEAD'
    });
    
    // Store checkpoint metadata
    await this.storeCheckpoint({
      id: checkpointId,
      name,
      description,
      timestamp: new Date(),
      baseCommit: await this.git.revparse('HEAD'),
      activeAgents: this.getActiveAgents()
    });
    
    return checkpointId;
  }
  
  async switchContext(targetCheckpoint: string) {
    // Save current context
    await this.saveCurrentContext();
    
    // Switch to checkpoint worktree
    await this.git.worktree.switch(targetCheckpoint);
    
    // Restore agent states
    await this.restoreAgentStates(targetCheckpoint);
  }
}
```

## Phase 2 UI/UX Enhancements

### 1. Multi-Agent Visualization
```typescript
// packages/ui/src/components/AgentVisualization.tsx
interface AgentVisualizationProps {
  workflow: ActiveWorkflow;
  onAgentClick: (agentId: string) => void;
}

export const AgentVisualization: React.FC<AgentVisualizationProps> = ({
  workflow,
  onAgentClick
}) => {
  return (
    <div className="relative h-full bg-neutral-50 dark:bg-neutral-900 rounded-lg p-6">
      {/* Agent nodes with status indicators */}
      {workflow.agents.map(agent => (
        <AgentNode
          key={agent.id}
          agent={agent}
          status={agent.status}
          progress={agent.progress}
          connections={agent.connections}
          onClick={() => onAgentClick(agent.id)}
        />
      ))}
      
      {/* Connection lines showing data flow */}
      <ConnectionLines agents={workflow.agents} />
      
      {/* Real-time progress indicators */}
      <ProgressOverlay workflow={workflow} />
    </div>
  );
};
```

### 2. Diff Visualization with CodeMirror
```typescript
// packages/ui/src/components/DiffEditor.tsx
import { EditorView } from '@codemirror/view';
import { MergeView } from '@codemirror/merge';

export const DiffEditor: React.FC<DiffEditorProps> = ({
  original,
  modified,
  onAccept,
  onReject
}) => {
  const [selectedChanges, setSelectedChanges] = useState<Set<string>>(new Set());
  
  return (
    <div className="h-full flex flex-col">
      <div className="flex-1 overflow-hidden">
        <MergeView
          original={original}
          modified={modified}
          highlightChanges={true}
          gutter={true}
          renderGutter={(change) => (
            <ChangeControl
              change={change}
              selected={selectedChanges.has(change.id)}
              onToggle={(id) => toggleChange(id)}
            />
          )}
        />
      </div>
      
      <div className="border-t border-neutral-200 dark:border-neutral-800 p-4">
        <div className="flex gap-2">
          <Button onClick={() => onAccept(selectedChanges)}>
            Accept Selected
          </Button>
          <Button variant="outline" onClick={() => onReject(selectedChanges)}>
            Reject Selected
          </Button>
          <Button variant="ghost" onClick={selectAll}>
            Select All
          </Button>
        </div>
      </div>
    </div>
  );
};
```

### 3. Voice Integration Foundation
```typescript
// packages/core/src/voice/integration.ts
import { generateText, streamText } from 'ai';

export class VoiceIntegration {
  private speechRecognition: SpeechRecognition;
  private speechSynthesis: SpeechSynthesis;
  
  async startVoiceCommand() {
    const transcript = await this.listenForCommand();
    
    // Process with Claude
    const response = await streamText({
      model: this.model,
      system: VOICE_COMMAND_PROMPT,
      prompt: transcript,
      tools: this.voiceTools
    });
    
    // Stream response to speech
    for await (const delta of response.textStream) {
      this.speakDelta(delta);
    }
  }
  
  private voiceTools = {
    executeIDECommand: tool({
      description: 'Execute IDE command from voice',
      parameters: z.object({
        command: z.enum(['open-file', 'run-workflow', 'search', 'navigate']),
        args: z.record(z.any())
      }),
      execute: async ({ command, args }) => {
        return this.ideCommands.execute(command, args);
      }
    })
  };
}
```

## Implementation Timeline (8 Weeks)

### Weeks 1-2: Agent System Foundation
- Base agent architecture
- Coordinator agent implementation
- Agent registry and lifecycle management
- Basic inter-agent communication

### Weeks 3-4: Workflow Engine v2
- Pattern implementations (sequential, parallel, routing)
- Workflow DSL and validation
- Visual workflow builder UI
- Workflow persistence and versioning

### Weeks 5-6: Advanced Features
- MCP integration with tool discovery
- Enhanced memory system
- Git worktree checkpoints
- Agent visualization UI

### Weeks 7-8: Polish & Integration
- Voice command integration
- Performance optimization
- Advanced diff visualization
- Comprehensive testing

## Performance Considerations

### 1. Agent Orchestration
```typescript
// Efficient agent pooling
class AgentPool {
  private available: Map<string, BaseAgent[]> = new Map();
  private busy: Map<string, BaseAgent> = new Map();
  
  async acquire(type: string): Promise<BaseAgent> {
    const pool = this.available.get(type) || [];
    if (pool.length > 0) {
      const agent = pool.pop()!;
      this.busy.set(agent.id, agent);
      return agent;
    }
    
    // Create new agent if pool is empty
    return this.createAgent(type);
  }
  
  release(agent: BaseAgent) {
    this.busy.delete(agent.id);
    const pool = this.available.get(agent.type) || [];
    pool.push(agent);
    this.available.set(agent.type, pool);
  }
}
```

### 2. Memory Optimization
- Implement sliding window for agent context
- Use compression for stored workflows
- Lazy load historical data
- Implement garbage collection for old checkpoints

## Testing Strategy

### 1. Agent Testing
```typescript
// Test harness for agents
describe('ExecutorAgent', () => {
  it('should handle file modifications correctly', async () => {
    const agent = new ExecutorAgent('frontend');
    const task = createTestTask('modify-component');
    
    const result = await agent.execute(task, mockContext);
    
    expect(result.filesModified).toHaveLength(1);
    expect(result.status).toBe('success');
  });
});
```

### 2. Integration Testing
- Multi-agent workflow scenarios
- MCP server integration tests
- Memory system persistence tests
- UI interaction tests

## Success Metrics

### Phase 2 Goals
- [ ] 5+ specialized agents working together
- [ ] Visual workflow builder operational
- [ ] MCP servers integrated successfully
- [ ] Memory system providing relevant context
- [ ] Workflow execution time < 30s for typical tasks
- [ ] Agent coordination overhead < 10%
- [ ] UI updates in real-time (< 100ms latency)

## Migration from Phase 1

### 1. Data Migration
```typescript
// Migrate Phase 1 sessions to Phase 2 format
export async function migratePhase1Data() {
  const oldSessions = await loadPhase1Sessions();
  
  for (const session of oldSessions) {
    const migrated = {
      ...session,
      workflow: createDefaultWorkflow(session),
      agents: ['coordinator'], // Default single agent
      memory: extractMemoryFromSession(session)
    };
    
    await savePhase2Session(migrated);
  }
}
```

### 2. API Compatibility
- Maintain Phase 1 endpoints with deprecation warnings
- Gradual migration path for plugins
- Backward compatibility for workflow configs

This plan positions the IDE as a cutting-edge development environment that leverages the full power of AI SDK v5 and Claude Code SDK, while maintaining the clean, performant foundation established in Phase 1.