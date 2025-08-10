import { test, expect, describe, beforeEach, mock } from 'bun:test';
import { Database } from 'bun:sqlite';
import { BaseAgent } from '../../src/agents/base-agent';
import { AgentConfig, AgentContext, AgentResult } from '../../src/types/agents';

// Test implementation of BaseAgent
class TestAgent extends BaseAgent {
  protected async validateInput(input: any): Promise<void> {
    if (!input.data) {
      throw new Error('Input data is required');
    }
  }
  
  protected async executeTask(input: any, context: AgentContext): Promise<any> {
    return {
      processed: input.data,
      agentId: this.config.id,
      timestamp: Date.now()
    };
  }
  
  protected async formatOutput(result: any): Promise<AgentResult> {
    return {
      success: true,
      data: result,
      metrics: {
        duration: 100,
        tokensUsed: 50
      }
    };
  }
}

describe('BaseAgent', () => {
  let db: Database;
  let agent: TestAgent;
  let config: AgentConfig;
  
  beforeEach(() => {
    // Create in-memory database
    db = new Database(':memory:');
    
    // Initialize config
    config = {
      id: 'test-agent',
      name: 'Test Agent',
      description: 'Agent for testing',
      capabilities: {
        maxTokens: 1000,
        preferredModel: 'claude-3-opus',
        fallbackModels: ['claude-3-sonnet'],
        temperature: 0.7,
        systemPromptTemplate: 'test-template',
        tools: ['read', 'write']
      },
      retryPolicy: {
        maxRetries: 3,
        backoffMs: 1000
      }
    };
    
    // Create agent
    agent = new TestAgent(config, db);
  });
  
  test('should initialize agent with correct config', () => {
    expect(agent.getId()).toBe('test-agent');
    expect(agent.getName()).toBe('Test Agent');
  });
  
  test('should execute task successfully', async () => {
    const input = { data: 'test input' };
    const context: AgentContext = {
      sessionId: 'session-123',
      workflowId: 'workflow-456',
      userId: 'user-789',
      workspace: '/test/workspace',
      variables: {}
    };
    
    const result = await agent.execute(input, context);
    
    expect(result.success).toBe(true);
    expect(result.data.processed).toBe('test input');
    expect(result.data.agentId).toBe('test-agent');
    expect(result.metrics).toBeDefined();
    expect(result.metrics.duration).toBe(100);
    expect(result.metrics.tokensUsed).toBe(50);
  });
  
  test('should validate input before execution', async () => {
    const invalidInput = {}; // Missing required 'data' field
    const context: AgentContext = {
      sessionId: 'session-123',
      workflowId: 'workflow-456',
      userId: 'user-789',
      workspace: '/test/workspace',
      variables: {}
    };
    
    await expect(agent.execute(invalidInput, context)).rejects.toThrow(
      'Input data is required'
    );
  });
  
  test('should track metrics in database', async () => {
    const input = { data: 'test input' };
    const context: AgentContext = {
      sessionId: 'session-123',
      workflowId: 'workflow-456',
      userId: 'user-789',
      workspace: '/test/workspace',
      variables: {}
    };
    
    await agent.execute(input, context);
    
    // Check if metrics were logged
    const metrics = db.query(
      'SELECT * FROM agent_metrics WHERE agent_id = ?'
    ).all('test-agent');
    
    expect(metrics.length).toBe(1);
    expect(metrics[0].agent_id).toBe('test-agent');
    expect(metrics[0].success).toBe(1);
  });
  
  test('should handle errors gracefully', async () => {
    // Override executeTask to throw error
    class ErrorAgent extends TestAgent {
      protected async executeTask(input: any, context: AgentContext): Promise<any> {
        throw new Error('Execution failed');
      }
    }
    
    const errorAgent = new ErrorAgent(config, db);
    const input = { data: 'test input' };
    const context: AgentContext = {
      sessionId: 'session-123',
      workflowId: 'workflow-456',
      userId: 'user-789',
      workspace: '/test/workspace',
      variables: {}
    };
    
    const result = await errorAgent.execute(input, context);
    
    expect(result.success).toBe(false);
    expect(result.error).toBe('Execution failed');
  });
  
  test('should retry on failure when configured', async () => {
    let attempts = 0;
    
    class RetryAgent extends TestAgent {
      protected async executeTask(input: any, context: AgentContext): Promise<any> {
        attempts++;
        if (attempts < 3) {
          throw new Error('Temporary failure');
        }
        return { processed: input.data, attempts };
      }
    }
    
    const retryAgent = new RetryAgent(config, db);
    const input = { data: 'test input' };
    const context: AgentContext = {
      sessionId: 'session-123',
      workflowId: 'workflow-456',
      userId: 'user-789',
      workspace: '/test/workspace',
      variables: {}
    };
    
    const result = await retryAgent.execute(input, context);
    
    expect(result.success).toBe(true);
    expect(result.data.attempts).toBe(3);
  });
  
  test('should emit events during execution', async () => {
    const events: string[] = [];
    
    agent.on('execution-start', () => events.push('start'));
    agent.on('execution-complete', () => events.push('complete'));
    
    const input = { data: 'test input' };
    const context: AgentContext = {
      sessionId: 'session-123',
      workflowId: 'workflow-456',
      userId: 'user-789',
      workspace: '/test/workspace',
      variables: {}
    };
    
    await agent.execute(input, context);
    
    expect(events).toEqual(['start', 'complete']);
  });
  
  test('should update context variables', async () => {
    class ContextAgent extends TestAgent {
      protected async executeTask(input: any, context: AgentContext): Promise<any> {
        context.variables.processed = true;
        context.variables.value = input.data;
        return { success: true };
      }
    }
    
    const contextAgent = new ContextAgent(config, db);
    const input = { data: 'test value' };
    const context: AgentContext = {
      sessionId: 'session-123',
      workflowId: 'workflow-456',
      userId: 'user-789',
      workspace: '/test/workspace',
      variables: {}
    };
    
    await contextAgent.execute(input, context);
    
    expect(context.variables.processed).toBe(true);
    expect(context.variables.value).toBe('test value');
  });
  
  test('should respect max execution time', async () => {
    class SlowAgent extends TestAgent {
      protected async executeTask(input: any, context: AgentContext): Promise<any> {
        await new Promise(resolve => setTimeout(resolve, 5000));
        return { processed: input.data };
      }
    }
    
    const slowConfig = {
      ...config,
      maxExecutionTime: 1000 // 1 second
    };
    
    const slowAgent = new SlowAgent(slowConfig, db);
    const input = { data: 'test input' };
    const context: AgentContext = {
      sessionId: 'session-123',
      workflowId: 'workflow-456',
      userId: 'user-789',
      workspace: '/test/workspace',
      variables: {}
    };
    
    const result = await slowAgent.execute(input, context);
    
    expect(result.success).toBe(false);
    expect(result.error).toContain('timeout');
  });
});

// Helper function to create test context
export function createTestContext(overrides?: Partial<AgentContext>): AgentContext {
  return {
    sessionId: 'test-session',
    workflowId: 'test-workflow',
    userId: 'test-user',
    workspace: '/test/workspace',
    variables: {},
    ...overrides
  };
}

// Helper function to create test config
export function createTestConfig(overrides?: Partial<AgentConfig>): AgentConfig {
  return {
    id: 'test-agent',
    name: 'Test Agent',
    description: 'Test agent for unit tests',
    capabilities: {
      maxTokens: 1000,
      preferredModel: 'claude-3-opus',
      fallbackModels: ['claude-3-sonnet'],
      temperature: 0.7,
      systemPromptTemplate: 'test',
      tools: []
    },
    ...overrides
  };
}