import { test, expect, describe, beforeEach, afterEach } from 'bun:test';
import { Database } from 'bun:sqlite';
import { WorkflowModeController } from '../../src/workflow/workflow-mode-controller';
import { PlannerAgent } from '../../src/agents/planner-agent';
import { EditorAgent } from '../../src/agents/editor-agent';
import { ReviewerAgent } from '../../src/agents/reviewer-agent';
import { SlashCommandRegistry } from '../../src/claude/slash-commands';
import { HookManager } from '../../src/claude/hooks';
import { $ } from 'bun';

describe('Workflow Integration', () => {
  let db: Database;
  let controller: WorkflowModeController;
  let commandRegistry: SlashCommandRegistry;
  let hookManager: HookManager;
  let testWorkspace: string;
  
  beforeEach(async () => {
    // Create test workspace
    testWorkspace = `/tmp/test-workspace-${Date.now()}`;
    await $`mkdir -p ${testWorkspace}`;
    
    // Create in-memory database
    db = new Database(':memory:');
    
    // Initialize components
    controller = new WorkflowModeController(testWorkspace, db);
    commandRegistry = new SlashCommandRegistry(testWorkspace, db);
    hookManager = new HookManager(testWorkspace, db);
  });
  
  afterEach(async () => {
    // Cleanup test workspace
    await $`rm -rf ${testWorkspace}`;
    db.close();
  });
  
  test('should complete full workflow: plan -> edit -> review', async () => {
    const sessionId = 'test-session';
    
    // Step 1: Start workflow with planning
    const workflowId = await controller.startWorkflow(
      sessionId,
      'Add a hello world function'
    );
    
    expect(workflowId).toBeDefined();
    
    // Check initial state
    let workflow = await controller.getWorkflow(workflowId);
    expect(workflow.mode).toBe('plan');
    expect(workflow.status).toBe('active');
    
    // Step 2: Transition to edit mode
    await controller.transitionMode(workflowId, 'edit');
    
    workflow = await controller.getWorkflow(workflowId);
    expect(workflow.mode).toBe('edit');
    
    // Step 3: Add some edits
    const edits = [
      {
        file: 'hello.ts',
        content: 'export function hello() { return "Hello, World!"; }'
      }
    ];
    
    await controller.addEdits(workflowId, edits);
    
    // Step 4: Transition to review mode
    await controller.transitionMode(workflowId, 'review');
    
    workflow = await controller.getWorkflow(workflowId);
    expect(workflow.mode).toBe('review');
    
    // Step 5: Complete workflow
    await controller.completeWorkflow(workflowId);
    
    workflow = await controller.getWorkflow(workflowId);
    expect(workflow.status).toBe('completed');
  });
  
  test('should execute slash commands in workflow', async () => {
    const sessionId = 'test-session';
    
    // Execute /plan command
    const planResult = await commandRegistry.execute('/plan Create user auth', {
      sessionId,
      workspace: testWorkspace
    });
    
    expect(planResult.success).toBe(true);
    expect(planResult.workflowId).toBeDefined();
    expect(planResult.mode).toBe('plan');
    
    const workflowId = planResult.workflowId;
    
    // Execute /status command
    const statusResult = await commandRegistry.execute('/status', {
      sessionId,
      workflowId,
      workspace: testWorkspace
    });
    
    expect(statusResult.success).toBe(true);
    expect(statusResult.mode).toBe('plan');
    expect(statusResult.status).toBe('active');
    
    // Execute /pause command
    const pauseResult = await commandRegistry.execute('/pause', {
      sessionId,
      workflowId,
      workspace: testWorkspace
    });
    
    expect(pauseResult.success).toBe(true);
    
    // Verify paused state
    const workflow = await controller.getWorkflow(workflowId);
    expect(workflow.status).toBe('paused');
    
    // Execute /resume command
    const resumeResult = await commandRegistry.execute('/resume', {
      sessionId,
      workflowId,
      workspace: testWorkspace
    });
    
    expect(resumeResult.success).toBe(true);
    expect(workflow.status).toBe('active');
  });
  
  test('should trigger hooks during workflow', async () => {
    const hookExecutions: string[] = [];
    
    // Register test hooks
    hookManager.register({
      id: 'test-pre-edit',
      type: 'pre',
      event: 'edit',
      priority: 10,
      enabled: true,
      handler: async (context) => {
        hookExecutions.push('pre-edit');
        return { continue: true };
      }
    });
    
    hookManager.register({
      id: 'test-post-edit',
      type: 'post',
      event: 'edit',
      priority: 5,
      enabled: true,
      handler: async (context) => {
        hookExecutions.push('post-edit');
        return { continue: true };
      }
    });
    
    // Start workflow
    const sessionId = 'test-session';
    const workflowId = await controller.startWorkflow(
      sessionId,
      'Test hooks'
    );
    
    // Transition to edit mode and trigger hooks
    await controller.transitionMode(workflowId, 'edit');
    
    // Simulate edit operation that triggers hooks
    const editContext = {
      data: {
        files: ['test.ts'],
        operation: 'edit'
      },
      sessionId,
      workflowId,
      workspace: testWorkspace
    };
    
    await hookManager.executeHooks('pre', 'edit', editContext);
    await hookManager.executeHooks('post', 'edit', editContext);
    
    expect(hookExecutions).toEqual(['pre-edit', 'post-edit']);
  });
  
  test('should handle workflow cancellation', async () => {
    const sessionId = 'test-session';
    
    // Start workflow
    const workflowId = await controller.startWorkflow(
      sessionId,
      'Test cancellation'
    );
    
    // Cancel workflow
    await controller.cancelWorkflow(workflowId);
    
    const workflow = await controller.getWorkflow(workflowId);
    expect(workflow.status).toBe('cancelled');
    
    // Verify cannot transition cancelled workflow
    await expect(
      controller.transitionMode(workflowId, 'edit')
    ).rejects.toThrow();
  });
  
  test('should handle multiple concurrent workflows', async () => {
    const sessionId = 'test-session';
    
    // Start multiple workflows
    const workflow1 = await controller.startWorkflow(
      sessionId,
      'Workflow 1'
    );
    
    const workflow2 = await controller.startWorkflow(
      sessionId,
      'Workflow 2'
    );
    
    const workflow3 = await controller.startWorkflow(
      sessionId,
      'Workflow 3'
    );
    
    // Get active workflows
    const activeWorkflows = controller.getActiveWorkflows();
    expect(activeWorkflows.length).toBe(3);
    
    // Complete one workflow
    await controller.completeWorkflow(workflow1);
    
    // Check active count
    const remainingActive = controller.getActiveWorkflows();
    expect(remainingActive.length).toBe(2);
    
    // Verify independent state
    const w1 = await controller.getWorkflow(workflow1);
    const w2 = await controller.getWorkflow(workflow2);
    const w3 = await controller.getWorkflow(workflow3);
    
    expect(w1.status).toBe('completed');
    expect(w2.status).toBe('active');
    expect(w3.status).toBe('active');
  });
  
  test('should persist workflow state across restarts', async () => {
    const sessionId = 'test-session';
    
    // Start workflow
    const workflowId = await controller.startWorkflow(
      sessionId,
      'Persistent workflow'
    );
    
    // Add some state
    await controller.transitionMode(workflowId, 'edit');
    await controller.addEdits(workflowId, [
      { file: 'test.ts', content: 'test content' }
    ]);
    
    // Create new controller instance (simulating restart)
    const newController = new WorkflowModeController(testWorkspace, db);
    
    // Load workflow from database
    const loadedWorkflow = await newController.getWorkflow(workflowId);
    
    expect(loadedWorkflow).toBeDefined();
    expect(loadedWorkflow.mode).toBe('edit');
    expect(loadedWorkflow.edits.length).toBe(1);
    expect(loadedWorkflow.edits[0].file).toBe('test.ts');
  });
  
  test('should validate mode transitions', async () => {
    const sessionId = 'test-session';
    
    const workflowId = await controller.startWorkflow(
      sessionId,
      'Test transitions'
    );
    
    // Valid transition: plan -> edit
    await controller.transitionMode(workflowId, 'edit');
    
    // Valid transition: edit -> review
    await controller.transitionMode(workflowId, 'review');
    
    // Invalid transition: review -> plan
    await expect(
      controller.transitionMode(workflowId, 'plan')
    ).rejects.toThrow('Invalid mode transition');
  });
  
  test('should track workflow progress', async () => {
    const sessionId = 'test-session';
    
    const workflowId = await controller.startWorkflow(
      sessionId,
      'Track progress'
    );
    
    // Initial progress
    let status = await controller.getStatus(workflowId);
    expect(status.progress).toBe(0);
    
    // Update progress
    await controller.updateProgress(workflowId, 25);
    status = await controller.getStatus(workflowId);
    expect(status.progress).toBe(25);
    
    // Transition mode updates progress
    await controller.transitionMode(workflowId, 'edit');
    status = await controller.getStatus(workflowId);
    expect(status.progress).toBeGreaterThan(25);
    
    // Complete workflow sets progress to 100
    await controller.completeWorkflow(workflowId);
    status = await controller.getStatus(workflowId);
    expect(status.progress).toBe(100);
  });
  
  test('should handle workflow errors gracefully', async () => {
    const sessionId = 'test-session';
    
    const workflowId = await controller.startWorkflow(
      sessionId,
      'Test errors'
    );
    
    // Add error to workflow
    await controller.addError(workflowId, 'Test error message');
    
    const workflow = await controller.getWorkflow(workflowId);
    expect(workflow.errors).toBeDefined();
    expect(workflow.errors.length).toBe(1);
    expect(workflow.errors[0]).toContain('Test error message');
    
    // Workflow should still be active despite error
    expect(workflow.status).toBe('active');
    
    // Can still complete workflow with errors
    await controller.completeWorkflow(workflowId);
    const completed = await controller.getWorkflow(workflowId);
    expect(completed.status).toBe('completed');
  });
});

// Helper to create test workflow
export async function createTestWorkflow(
  controller: WorkflowModeController,
  task: string = 'Test task'
): Promise<string> {
  return await controller.startWorkflow('test-session', task);
}