import { BaseAgent } from './base-agent';
import { 
  AgentCapabilities, 
  AgentContext, 
  AgentResult,
  Plan,
  PlanStep,
  FileOperation
} from '../types/agents';
import { Database } from 'bun:sqlite';

export class PlannerAgent extends BaseAgent {
  constructor(workspace: string, db: Database) {
    super('planner', workspace, db);
  }
  
  defineCapabilities(): AgentCapabilities {
    return {
      maxTokens: 8000,
      preferredModel: 'claude-3-opus',
      fallbackModels: ['gpt-4-turbo', 'claude-3-sonnet'],
      temperature: 0.3,
      systemPromptTemplate: 'planner-system-v1',
      tools: ['file_tree', 'symbol_search', 'dependency_graph']
    };
  }
  
  validateInput(context: AgentContext): boolean {
    // Ensure we have a task string
    if (!context.task || typeof context.task !== 'string') {
      return false;
    }
    
    // Ensure workspace is valid
    if (!context.workspace || typeof context.workspace !== 'string') {
      return false;
    }
    
    return true;
  }
  
  async formatContext(context: AgentContext): Promise<any> {
    // Get full repository context for planning
    const repoContext = await this.contextGenerator.generateContext({
      maxTokens: 6000,
      includeFileMap: true,
      includeCodeMap: true,
      includeContent: false // Don't need full content for planning
    });
    
    // Get working set for recent context
    const workingSet = await this.contextGenerator['workingSetTracker'].getWorkingSet();
    
    return {
      task: context.task,
      repoStructure: repoContext.fileMap,
      codeSymbols: repoContext.codeMap,
      recentFiles: workingSet.recentlyModified,
      gitStatus: workingSet.gitChanges,
      constraints: context.constraints || [],
      successCriteria: context.successCriteria || []
    };
  }
  
  processResult(rawResult: any): AgentResult {
    try {
      // Parse the plan from model output
      const plan = this.parsePlan(rawResult.content);
      
      // Validate plan structure
      this.validatePlan(plan);
      
      // Optimize step ordering
      const optimizedPlan = this.optimizePlanOrder(plan);
      
      return {
        success: true,
        output: optimizedPlan,
        tokensUsed: rawResult.tokensUsed,
        modelUsed: rawResult.model,
        duration: 0, // Will be set by base class
        nextSteps: optimizedPlan.steps.map(s => s.description)
      };
    } catch (error) {
      return {
        success: false,
        output: null,
        tokensUsed: rawResult.tokensUsed || 0,
        modelUsed: rawResult.model || 'unknown',
        duration: 0,
        errors: [error.message]
      };
    }
  }
  
  private parsePlan(content: string): Plan {
    const steps: PlanStep[] = [];
    const successCriteria: string[] = [];
    const risks: string[] = [];
    
    // Parse step sections
    const stepMatches = content.matchAll(/### STEP (\d+): (.*?)\n([\s\S]*?)(?=### STEP|### SUCCESS|### RISKS|$)/gi);
    for (const match of stepMatches) {
      const [_, id, description, details] = match;
      steps.push(this.parseStep(id, description, details));
    }
    
    // Parse success criteria
    const criteriaMatch = content.match(/### SUCCESS CRITERIA\n([\s\S]*?)(?=###|$)/i);
    if (criteriaMatch) {
      const criteriaLines = criteriaMatch[1].split('\n').filter(line => line.trim());
      for (const line of criteriaLines) {
        const cleaned = line.replace(/^[-*\[\]\s]+/, '').trim();
        if (cleaned) successCriteria.push(cleaned);
      }
    }
    
    // Parse risks
    const risksMatch = content.match(/### RISKS\n([\s\S]*?)(?=###|$)/i);
    if (risksMatch) {
      const riskLines = risksMatch[1].split('\n').filter(line => line.trim());
      for (const line of riskLines) {
        const cleaned = line.replace(/^[-*\s]+/, '').trim();
        if (cleaned) risks.push(cleaned);
      }
    }
    
    return {
      steps,
      successCriteria,
      estimatedTotalTokens: steps.reduce((sum, s) => sum + s.estimatedTokens, 0),
      estimatedDuration: steps.length * 2000, // 2 seconds per step estimate
      risks
    };
  }
  
  private parseStep(id: string, description: string, details: string): PlanStep {
    const fileOperations: FileOperation[] = [];
    const dependencies: string[] = [];
    let assignedAgent: 'editor' | 'reviewer' | 'grunt' = 'editor';
    let estimatedTokens = 1000; // Default estimate
    
    // Parse files to modify
    const modifyMatch = details.match(/\*\*Files to modify:\*\*([\s\S]*?)(?=\*\*|$)/i);
    if (modifyMatch) {
      const files = modifyMatch[1].split('\n').filter(line => line.includes(':'));
      for (const file of files) {
        const [path, desc] = file.split(':').map(s => s.trim().replace(/^-\s*/, ''));
        if (path) {
          fileOperations.push({
            type: 'edit',
            path,
            description: desc || 'Modify file',
            priority: 1
          });
        }
      }
    }
    
    // Parse files to create
    const createMatch = details.match(/\*\*Files to create:\*\*([\s\S]*?)(?=\*\*|$)/i);
    if (createMatch) {
      const files = createMatch[1].split('\n').filter(line => line.includes(':'));
      for (const file of files) {
        const [path, desc] = file.split(':').map(s => s.trim().replace(/^-\s*/, ''));
        if (path) {
          fileOperations.push({
            type: 'create',
            path,
            description: desc || 'Create file',
            priority: 2
          });
        }
      }
    }
    
    // Parse dependencies
    const depMatch = details.match(/\*\*Dependencies:\*\*\s*(.*?)(?:\n|$)/i);
    if (depMatch) {
      const depText = depMatch[1].trim();
      if (depText && depText.toLowerCase() !== 'none') {
        const depIds = depText.match(/Step\s+(\d+)/gi);
        if (depIds) {
          for (const depId of depIds) {
            dependencies.push(depId.replace(/Step\s+/i, ''));
          }
        }
      }
    }
    
    // Parse assigned agent
    const agentMatch = details.match(/\*\*Assigned to:\*\*\s*(.*?)(?:\n|$)/i);
    if (agentMatch) {
      const agent = agentMatch[1].trim().toLowerCase();
      if (agent === 'reviewer' || agent === 'grunt') {
        assignedAgent = agent;
      }
    }
    
    // Parse estimated tokens
    const tokensMatch = details.match(/\*\*Estimated tokens:\*\*\s*(\d+)/i);
    if (tokensMatch) {
      estimatedTokens = parseInt(tokensMatch[1], 10);
    }
    
    return {
      id: `step-${id}`,
      description: description.trim(),
      fileOperations,
      dependencies,
      estimatedTokens,
      assignedAgent
    };
  }
  
  private validatePlan(plan: Plan) {
    if (!plan.steps || plan.steps.length === 0) {
      throw new Error('Plan must contain at least one step');
    }
    
    if (!plan.successCriteria || plan.successCriteria.length === 0) {
      throw new Error('Plan must define success criteria');
    }
    
    // Check for circular dependencies
    for (const step of plan.steps) {
      if (step.dependencies.includes(step.id)) {
        throw new Error(`Step ${step.id} cannot depend on itself`);
      }
    }
    
    // Validate all dependencies exist
    const stepIds = new Set(plan.steps.map(s => s.id));
    for (const step of plan.steps) {
      for (const dep of step.dependencies) {
        const depId = dep.startsWith('step-') ? dep : `step-${dep}`;
        if (!stepIds.has(depId)) {
          throw new Error(`Step ${step.id} depends on non-existent step ${dep}`);
        }
      }
    }
  }
  
  private optimizePlanOrder(plan: Plan): Plan {
    // Topological sort based on dependencies
    const sorted = this.topologicalSort(plan.steps);
    
    // Group independent steps for parallel execution
    const parallelGroups = this.groupParallelSteps(sorted);
    
    return {
      ...plan,
      steps: sorted,
      parallelGroups
    };
  }
  
  private topologicalSort(steps: PlanStep[]): PlanStep[] {
    const sorted: PlanStep[] = [];
    const visited = new Set<string>();
    const visiting = new Set<string>();
    
    const visit = (step: PlanStep) => {
      if (visited.has(step.id)) return;
      if (visiting.has(step.id)) {
        throw new Error('Circular dependency detected in plan');
      }
      
      visiting.add(step.id);
      
      // Visit dependencies first
      for (const depId of step.dependencies) {
        const fullDepId = depId.startsWith('step-') ? depId : `step-${depId}`;
        const dep = steps.find(s => s.id === fullDepId);
        if (dep) {
          visit(dep);
        }
      }
      
      visiting.delete(step.id);
      visited.add(step.id);
      sorted.push(step);
    };
    
    for (const step of steps) {
      visit(step);
    }
    
    return sorted;
  }
  
  private groupParallelSteps(steps: PlanStep[]): PlanStep[][] {
    const groups: PlanStep[][] = [];
    const processed = new Set<string>();
    
    for (const step of steps) {
      if (processed.has(step.id)) continue;
      
      // Find all steps that can be executed in parallel with this one
      const group: PlanStep[] = [step];
      processed.add(step.id);
      
      for (const other of steps) {
        if (processed.has(other.id)) continue;
        
        // Check if 'other' can be executed in parallel with all steps in 'group'
        let canParallel = true;
        
        for (const groupStep of group) {
          // Check if there's a dependency between them
          if (this.hasDependency(groupStep, other, steps) || 
              this.hasDependency(other, groupStep, steps)) {
            canParallel = false;
            break;
          }
          
          // Check if they modify the same files
          if (this.hasFileConflict(groupStep, other)) {
            canParallel = false;
            break;
          }
        }
        
        if (canParallel) {
          group.push(other);
          processed.add(other.id);
        }
      }
      
      groups.push(group);
    }
    
    return groups;
  }
  
  private hasDependency(step1: PlanStep, step2: PlanStep, allSteps: PlanStep[]): boolean {
    // Direct dependency
    if (step1.dependencies.includes(step2.id) || 
        step1.dependencies.includes(step2.id.replace('step-', ''))) {
      return true;
    }
    
    // Transitive dependency (simplified check)
    const step1Deps = this.getAllDependencies(step1, allSteps);
    return step1Deps.has(step2.id);
  }
  
  private getAllDependencies(step: PlanStep, allSteps: PlanStep[]): Set<string> {
    const deps = new Set<string>();
    const queue = [...step.dependencies];
    
    while (queue.length > 0) {
      const depId = queue.shift()!;
      const fullDepId = depId.startsWith('step-') ? depId : `step-${depId}`;
      
      if (deps.has(fullDepId)) continue;
      deps.add(fullDepId);
      
      const depStep = allSteps.find(s => s.id === fullDepId);
      if (depStep) {
        queue.push(...depStep.dependencies);
      }
    }
    
    return deps;
  }
  
  private hasFileConflict(step1: PlanStep, step2: PlanStep): boolean {
    const files1 = new Set(step1.fileOperations.map(op => op.path));
    const files2 = new Set(step2.fileOperations.map(op => op.path));
    
    for (const file of files1) {
      if (files2.has(file)) {
        return true;
      }
    }
    
    return false;
  }
}