import { Hono } from 'hono';
import { WorkflowEngine, analyzeExecuteWorkflow } from '@devys/core';
import { ClaudeCodeLanguageModel } from '@devys/core';
import type { 
  WorkflowConfig, 
  WorkflowProgressEvent 
} from '@devys/types';
import { z } from 'zod';
import { wsManager } from '../ws/websocket';

const workflow = new Hono();

// Workflow engine instance
let workflowEngine: WorkflowEngine | null = null;

// Initialize workflow engine
function getWorkflowEngine() {
  if (!workflowEngine) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new Error('ANTHROPIC_API_KEY environment variable is required');
    }

    const model = new ClaudeCodeLanguageModel({
      apiKey,
      model: 'sonnet'
    });

    workflowEngine = new WorkflowEngine(model);

    // Listen for progress events
    workflowEngine.on('progress', (event: WorkflowProgressEvent) => {
      // Broadcast to all connected WebSocket clients
      wsManager.broadcast({ 
        type: 'workflow:progress', 
        event 
      });
    });
  }

  return workflowEngine;
}

// Start a workflow
workflow.post('/start', async (c) => {
  try {
    const body = await c.req.json();
    
    // Validate request
    const requestSchema = z.object({
      template: z.string().optional(),
      config: z.object({
        version: z.string(),
        name: z.string(),
        description: z.string(),
        steps: z.array(z.any())
      }).optional(),
      sessionId: z.string().optional()
    });

    const { template, config, sessionId } = requestSchema.parse(body);

    // Get workflow configuration
    let workflowConfig: WorkflowConfig;
    if (template === 'analyze-execute') {
      workflowConfig = analyzeExecuteWorkflow;
    } else if (config) {
      workflowConfig = config;
    } else {
      return c.json({ error: 'Either template or config must be provided' }, 400);
    }

    // Start workflow
    const engine = getWorkflowEngine();
    const executionId = await engine.startWorkflow(workflowConfig, sessionId);

    return c.json({ 
      executionId,
      message: 'Workflow started successfully' 
    });
  } catch (error) {
    console.error('Error starting workflow:', error);
    return c.json({ 
      error: error instanceof Error ? error.message : 'Failed to start workflow' 
    }, 500);
  }
});

// Get workflow execution status
workflow.get('/execution/:id', (c) => {
  try {
    const executionId = c.req.param('id');
    const engine = getWorkflowEngine();
    const execution = engine.getExecution(executionId);

    if (!execution) {
      return c.json({ error: 'Execution not found' }, 404);
    }

    return c.json(execution);
  } catch (error) {
    console.error('Error getting execution:', error);
    return c.json({ 
      error: error instanceof Error ? error.message : 'Failed to get execution' 
    }, 500);
  }
});

// List all executions
workflow.get('/executions', (c) => {
  try {
    const engine = getWorkflowEngine();
    const executions = engine.getAllExecutions();
    
    return c.json({ executions });
  } catch (error) {
    console.error('Error listing executions:', error);
    return c.json({ 
      error: error instanceof Error ? error.message : 'Failed to list executions' 
    }, 500);
  }
});

// Cancel a workflow
workflow.post('/execution/:id/cancel', (c) => {
  try {
    const executionId = c.req.param('id');
    const engine = getWorkflowEngine();
    
    engine.cancelWorkflow(executionId);
    
    return c.json({ 
      message: 'Workflow cancelled successfully' 
    });
  } catch (error) {
    console.error('Error cancelling workflow:', error);
    return c.json({ 
      error: error instanceof Error ? error.message : 'Failed to cancel workflow' 
    }, 500);
  }
});

// Approve a workflow step
workflow.post('/execution/:executionId/step/:stepId/approve', (c) => {
  try {
    const { executionId, stepId } = c.req.param();
    const engine = getWorkflowEngine();
    
    engine.approveStep(executionId, stepId);
    
    return c.json({ 
      message: 'Step approved successfully' 
    });
  } catch (error) {
    console.error('Error approving step:', error);
    return c.json({ 
      error: error instanceof Error ? error.message : 'Failed to approve step' 
    }, 500);
  }
});

// Reject a workflow step
workflow.post('/execution/:executionId/step/:stepId/reject', (c) => {
  try {
    const { executionId, stepId } = c.req.param();
    const engine = getWorkflowEngine();
    
    engine.rejectStep(executionId, stepId);
    
    return c.json({ 
      message: 'Step rejected successfully' 
    });
  } catch (error) {
    console.error('Error rejecting step:', error);
    return c.json({ 
      error: error instanceof Error ? error.message : 'Failed to reject step' 
    }, 500);
  }
});

// Export workflow route
export { workflow };