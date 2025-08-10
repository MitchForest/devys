import { 
  AgentCapabilities, 
  AgentContext, 
  AgentResult 
} from '../types/agents';
import { PromptManager } from '../prompts/prompt-manager';
import { ModelRouter } from '../routing/model-router';
import { ContextGenerator } from '../services/context/context-generator';
import { Database } from 'bun:sqlite';

export abstract class BaseAgent {
  protected capabilities: AgentCapabilities;
  protected promptManager: PromptManager;
  protected modelRouter: ModelRouter;
  protected contextGenerator: ContextGenerator;
  
  constructor(
    protected name: string,
    protected workspace: string,
    protected db: Database
  ) {
    this.capabilities = this.defineCapabilities();
    this.promptManager = new PromptManager(db);
    this.modelRouter = new ModelRouter();
    this.contextGenerator = new ContextGenerator(workspace, db);
  }
  
  abstract defineCapabilities(): AgentCapabilities;
  abstract validateInput(context: AgentContext): boolean;
  abstract formatContext(context: AgentContext): Promise<any>;
  abstract processResult(rawResult: any): AgentResult;
  
  async execute(context: AgentContext): Promise<AgentResult> {
    const startTime = Date.now();
    
    try {
      // Validate input
      if (!this.validateInput(context)) {
        throw new Error(`Invalid input for ${this.name} agent`);
      }
      
      // Generate context based on agent needs
      const formattedContext = await this.formatContext(context);
      
      // Build prompt from template
      const prompt = await this.promptManager.buildPrompt(
        this.capabilities.systemPromptTemplate,
        formattedContext
      );
      
      // Route to appropriate model
      const result = await this.modelRouter.route({
        prompt,
        preferredModel: this.capabilities.preferredModel,
        fallbackModels: this.capabilities.fallbackModels,
        maxTokens: this.capabilities.maxTokens,
        temperature: this.capabilities.temperature,
        complexity: this.inferComplexity(context)
      });
      
      // Process and return result
      const processed = this.processResult(result);
      
      // Add timing information
      processed.duration = Date.now() - startTime;
      
      // Log metrics
      await this.logMetrics(processed);
      
      return processed;
      
    } catch (error) {
      console.error(`Agent ${this.name} execution failed:`, error);
      
      return {
        success: false,
        output: null,
        tokensUsed: 0,
        modelUsed: 'none',
        duration: Date.now() - startTime,
        errors: [error.message]
      };
    }
  }
  
  protected inferComplexity(context: AgentContext): 'simple' | 'moderate' | 'complex' {
    // Default implementation - can be overridden
    const taskString = JSON.stringify(context.task);
    
    if (taskString.length < 500) return 'simple';
    if (taskString.length < 2000) return 'moderate';
    return 'complex';
  }
  
  protected async logMetrics(result: AgentResult) {
    // Log to database for analysis
    this.db.run(
      `INSERT INTO agent_metrics (agent, success, tokens_used, model_used, duration, timestamp)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        this.name,
        result.success ? 1 : 0,
        result.tokensUsed,
        result.modelUsed,
        result.duration,
        Date.now()
      ]
    );
  }
  
  getCapabilities(): AgentCapabilities {
    return this.capabilities;
  }
  
  getName(): string {
    return this.name;
  }
}