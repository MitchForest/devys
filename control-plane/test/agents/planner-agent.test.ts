import { test, expect, describe, beforeEach } from 'bun:test';
import { Database } from 'bun:sqlite';
import { PlannerAgent } from '../../src/agents/planner-agent';
import { AgentContext, Task } from '../../src/types/agents';
import { createTestContext, createTestConfig } from './base-agent.test';

describe('PlannerAgent', () => {
  let db: Database;
  let planner: PlannerAgent;
  
  beforeEach(() => {
    db = new Database(':memory:');
    planner = new PlannerAgent(db);
  });
  
  test('should decompose simple task into steps', async () => {
    const input = {
      task: 'Add a new button to the homepage',
      requirements: [
        'Button should be blue',
        'Button should say "Get Started"',
        'Button should link to /signup'
      ]
    };
    
    const context = createTestContext();
    const result = await planner.execute(input, context);
    
    expect(result.success).toBe(true);
    expect(result.data.tasks).toBeDefined();
    expect(result.data.tasks.length).toBeGreaterThan(0);
    
    // Check task structure
    const firstTask = result.data.tasks[0];
    expect(firstTask.id).toBeDefined();
    expect(firstTask.name).toBeDefined();
    expect(firstTask.description).toBeDefined();
    expect(firstTask.type).toBeDefined();
    expect(firstTask.priority).toBeDefined();
  });
  
  test('should identify task dependencies', async () => {
    const input = {
      task: 'Create a user authentication system',
      requirements: [
        'User registration',
        'Login functionality',
        'Password reset',
        'Session management'
      ]
    };
    
    const context = createTestContext();
    const result = await planner.execute(input, context);
    
    expect(result.success).toBe(true);
    
    // Find tasks with dependencies
    const tasksWithDeps = result.data.tasks.filter(
      (t: Task) => t.dependencies && t.dependencies.length > 0
    );
    
    expect(tasksWithDeps.length).toBeGreaterThan(0);
    
    // Verify dependency ordering
    for (const task of tasksWithDeps) {
      for (const depId of task.dependencies!) {
        const depTask = result.data.tasks.find((t: Task) => t.id === depId);
        expect(depTask).toBeDefined();
        expect(depTask.priority).toBeLessThan(task.priority);
      }
    }
  });
  
  test('should identify parallel task groups', async () => {
    const input = {
      task: 'Refactor three independent components',
      requirements: [
        'Refactor Header component',
        'Refactor Footer component',
        'Refactor Sidebar component'
      ]
    };
    
    const context = createTestContext();
    const result = await planner.execute(input, context);
    
    expect(result.success).toBe(true);
    expect(result.data.parallelGroups).toBeDefined();
    expect(result.data.parallelGroups.length).toBeGreaterThan(0);
    
    // Check that independent tasks are in same parallel group
    const firstGroup = result.data.parallelGroups[0];
    expect(firstGroup.length).toBeGreaterThan(1);
  });
  
  test('should perform topological sort on tasks', async () => {
    const input = {
      task: 'Build a feature with dependencies',
      requirements: [
        'Create database schema',
        'Build API endpoints',
        'Create frontend components',
        'Write tests'
      ]
    };
    
    const context = createTestContext();
    const result = await planner.execute(input, context);
    
    expect(result.success).toBe(true);
    expect(result.data.executionOrder).toBeDefined();
    
    // Verify topological ordering
    const order = result.data.executionOrder;
    const taskMap = new Map(result.data.tasks.map((t: Task) => [t.id, t]));
    
    for (let i = 0; i < order.length; i++) {
      const task = taskMap.get(order[i]);
      if (task?.dependencies) {
        for (const depId of task.dependencies) {
          const depIndex = order.indexOf(depId);
          expect(depIndex).toBeLessThan(i);
        }
      }
    }
  });
  
  test('should estimate resources for tasks', async () => {
    const input = {
      task: 'Implement a complex feature',
      complexity: 'high'
    };
    
    const context = createTestContext();
    const result = await planner.execute(input, context);
    
    expect(result.success).toBe(true);
    
    // Check resource estimates
    for (const task of result.data.tasks) {
      expect(task.estimatedTokens).toBeDefined();
      expect(task.estimatedTokens).toBeGreaterThan(0);
      
      if (task.metadata) {
        expect(task.metadata.estimatedTime).toBeDefined();
        expect(task.metadata.complexity).toBeDefined();
      }
    }
  });
  
  test('should handle empty task gracefully', async () => {
    const input = {
      task: ''
    };
    
    const context = createTestContext();
    const result = await planner.execute(input, context);
    
    expect(result.success).toBe(false);
    expect(result.error).toContain('Task description is required');
  });
  
  test('should generate appropriate task types', async () => {
    const input = {
      task: 'Fix bug, add feature, and update docs',
      requirements: [
        'Fix null pointer exception',
        'Add dark mode toggle',
        'Update API documentation'
      ]
    };
    
    const context = createTestContext();
    const result = await planner.execute(input, context);
    
    expect(result.success).toBe(true);
    
    const taskTypes = result.data.tasks.map((t: Task) => t.type);
    expect(taskTypes).toContain('fix');
    expect(taskTypes).toContain('feature');
    expect(taskTypes).toContain('documentation');
  });
  
  test('should include affected files in tasks', async () => {
    const input = {
      task: 'Update user profile component',
      files: [
        'src/components/UserProfile.tsx',
        'src/styles/profile.css',
        'src/api/user.ts'
      ]
    };
    
    const context = createTestContext();
    const result = await planner.execute(input, context);
    
    expect(result.success).toBe(true);
    
    // Check that tasks reference the provided files
    const allFiles = result.data.tasks.flatMap(
      (t: Task) => t.affectedFiles || []
    );
    
    expect(allFiles.length).toBeGreaterThan(0);
    expect(allFiles.some(f => f.includes('UserProfile')));
  });
  
  test('should optimize execution plan', async () => {
    const input = {
      task: 'Optimize database queries and add caching',
      optimize: true
    };
    
    const context = createTestContext();
    const result = await planner.execute(input, context);
    
    expect(result.success).toBe(true);
    expect(result.data.optimized).toBe(true);
    
    // Check optimization metrics
    expect(result.data.metrics).toBeDefined();
    expect(result.data.metrics.estimatedTotalTime).toBeDefined();
    expect(result.data.metrics.parallelizationFactor).toBeDefined();
    expect(result.data.metrics.parallelizationFactor).toBeGreaterThan(0);
  });
  
  test('should persist plan to database', async () => {
    const input = {
      task: 'Create a test plan',
      persist: true
    };
    
    const context = createTestContext();
    const result = await planner.execute(input, context);
    
    expect(result.success).toBe(true);
    
    // Check database for saved plan
    const plans = db.query(
      'SELECT * FROM plans WHERE workflow_id = ?'
    ).all(context.workflowId);
    
    expect(plans.length).toBe(1);
    expect(plans[0].workflow_id).toBe(context.workflowId);
  });
  
  test('should handle complex nested requirements', async () => {
    const input = {
      task: 'Build e-commerce platform',
      requirements: {
        frontend: [
          'Product listing',
          'Shopping cart',
          'Checkout flow'
        ],
        backend: [
          'API endpoints',
          'Database schema',
          'Payment integration'
        ],
        infrastructure: [
          'CI/CD pipeline',
          'Monitoring',
          'Scaling'
        ]
      }
    };
    
    const context = createTestContext();
    const result = await planner.execute(input, context);
    
    expect(result.success).toBe(true);
    
    // Should create tasks for all requirement categories
    const taskNames = result.data.tasks.map((t: Task) => t.name.toLowerCase());
    
    expect(taskNames.some(n => n.includes('frontend')));
    expect(taskNames.some(n => n.includes('backend')));
    expect(taskNames.some(n => n.includes('infrastructure')));
  });
});

// Integration test helpers
export async function createTestPlan(
  planner: PlannerAgent,
  task: string
): Promise<Task[]> {
  const result = await planner.execute(
    { task },
    createTestContext()
  );
  
  if (!result.success) {
    throw new Error(result.error);
  }
  
  return result.data.tasks;
}