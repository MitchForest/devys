import { Database } from 'bun:sqlite';
import {
  PromptTemplate,
  VariableDefinition,
  Example,
  ComparisonResult
} from '../types/prompts';

export class PromptManager {
  private templates: Map<string, PromptTemplate>;
  private activeTemplates: Map<string, string>; // agent -> template id
  private db: Database;
  
  constructor(db: Database) {
    this.db = db;
    this.templates = new Map();
    this.activeTemplates = new Map();
    
    this.initializeDatabase();
    this.loadTemplates();
    this.loadActiveTemplates();
  }
  
  private initializeDatabase() {
    // Create tables if they don't exist
    this.db.run(`
      CREATE TABLE IF NOT EXISTS prompt_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        version TEXT NOT NULL,
        agent TEXT NOT NULL,
        template TEXT NOT NULL,
        variables TEXT NOT NULL,
        examples TEXT,
        metadata TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        modified_at INTEGER NOT NULL
      )
    `);
    
    this.db.run(`
      CREATE TABLE IF NOT EXISTS active_templates (
        agent TEXT PRIMARY KEY,
        template_id TEXT NOT NULL,
        activated_at INTEGER NOT NULL,
        FOREIGN KEY (template_id) REFERENCES prompt_templates(id)
      )
    `);
    
    this.db.run(`
      CREATE TABLE IF NOT EXISTS template_performance (
        template_id TEXT NOT NULL,
        tokens_used INTEGER,
        duration INTEGER,
        success INTEGER,
        timestamp INTEGER,
        FOREIGN KEY (template_id) REFERENCES prompt_templates(id)
      )
    `);
  }
  
  private loadTemplates() {
    const rows = this.db.query(
      "SELECT * FROM prompt_templates"
    ).all() as any[];
    
    for (const row of rows) {
      const template: PromptTemplate = {
        id: row.id,
        name: row.name,
        version: row.version,
        agent: row.agent,
        template: row.template,
        variables: JSON.parse(row.variables),
        examples: row.examples ? JSON.parse(row.examples) : undefined,
        metadata: JSON.parse(row.metadata)
      };
      
      // Convert date strings back to Date objects
      template.metadata.created = new Date(template.metadata.created);
      template.metadata.modified = new Date(template.metadata.modified);
      
      this.templates.set(template.id, template);
    }
    
    // Load default templates if none exist
    if (this.templates.size === 0) {
      this.loadDefaultTemplates();
    }
  }
  
  private loadDefaultTemplates() {
    // These would be imported from template files in production
    // For now, we'll create them inline
    console.log('Loading default prompt templates...');
    
    // Import default templates (we'll create these next)
    // For now, create a simple planner template
    const plannerTemplate: PromptTemplate = {
      id: 'planner-system-v1',
      name: 'Planner System Prompt',
      version: '1.0.0',
      agent: 'planner',
      template: this.getDefaultPlannerTemplate(),
      variables: this.getDefaultPlannerVariables(),
      metadata: {
        author: 'system',
        created: new Date(),
        modified: new Date(),
        performance: {
          avgTokensUsed: 3500,
          avgDuration: 2500,
          successRate: 0.92
        }
      }
    };
    
    this.createTemplate(plannerTemplate);
  }
  
  private getDefaultPlannerTemplate(): string {
    return `You are a senior software architect tasked with planning the implementation of a development task.

## Your Role
- Analyze the codebase structure and existing patterns
- Break down the task into clear, actionable steps
- Identify dependencies and potential risks
- Define clear success criteria

## Context
Task: {{task}}

Repository Structure:
{{repoStructure}}

Code Symbols:
{{codeSymbols}}

Recent Activity:
- Recently modified files: {{recentFiles}}
- Git changes: {{gitStatus}}

## Constraints
{{constraints}}

## Instructions
1. Analyze the task and codebase to understand what needs to be done
2. Create a step-by-step plan with specific file operations
3. For each step, specify:
   - Clear description of what needs to be done
   - Which files need to be created/modified/deleted
   - Any dependencies on other steps
   - Which agent should handle it (editor for code changes, reviewer for validation)
4. Define success criteria that can be objectively verified
5. Identify potential risks or complications

## Output Format
Structure your response as follows:

### STEP 1: [Brief description]
**Files to modify:**
- path/to/file1.ts: [what changes]
- path/to/file2.ts: [what changes]

**Files to create:**
- path/to/newfile.ts: [purpose]

**Dependencies:** None | Step X
**Assigned to:** editor | reviewer
**Estimated tokens:** [number]

### STEP 2: [Brief description]
...

### SUCCESS CRITERIA
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

### RISKS
- Risk 1: [description and mitigation]
- Risk 2: [description and mitigation]

Be specific and actionable. Each step should be independently verifiable.`;
  }
  
  private getDefaultPlannerVariables(): VariableDefinition[] {
    return [
      {
        name: 'task',
        type: 'string',
        required: true,
        description: 'The user task to plan'
      },
      {
        name: 'repoStructure',
        type: 'object',
        required: true,
        description: 'File map of the repository'
      },
      {
        name: 'codeSymbols',
        type: 'object',
        required: true,
        description: 'Code map with symbols'
      },
      {
        name: 'recentFiles',
        type: 'array',
        required: false,
        default: [],
        description: 'Recently modified files'
      },
      {
        name: 'gitStatus',
        type: 'array',
        required: false,
        default: [],
        description: 'Current git changes'
      },
      {
        name: 'constraints',
        type: 'array',
        required: false,
        default: [],
        description: 'Task constraints'
      }
    ];
  }
  
  private loadActiveTemplates() {
    const rows = this.db.query(
      "SELECT * FROM active_templates"
    ).all() as any[];
    
    for (const row of rows) {
      this.activeTemplates.set(row.agent, row.template_id);
    }
    
    // Set defaults if none are active
    if (this.activeTemplates.size === 0) {
      this.activeTemplates.set('planner', 'planner-system-v1');
      this.activeTemplates.set('editor', 'editor-system-v1');
      this.activeTemplates.set('reviewer', 'reviewer-system-v1');
    }
  }
  
  async buildPrompt(templateId: string, context: any): Promise<string> {
    const template = this.templates.get(templateId);
    if (!template) {
      // Try to get default template for agent
      const agentMatch = templateId.match(/^(\w+)-/);
      if (agentMatch) {
        const agent = agentMatch[1];
        const activeId = this.activeTemplates.get(agent);
        if (activeId) {
          return this.buildPrompt(activeId, context);
        }
      }
      throw new Error(`Template ${templateId} not found`);
    }
    
    // Validate all required variables are present
    this.validateContext(template, context);
    
    // Interpolate variables
    let prompt = template.template;
    
    for (const variable of template.variables) {
      const value = context[variable.name] ?? variable.default;
      const formatted = this.formatValue(value, variable.type);
      
      // Replace all occurrences of {{variable}}
      const regex = new RegExp(`{{${variable.name}}}`, 'g');
      prompt = prompt.replace(regex, formatted);
    }
    
    // Add examples if provided
    if (template.examples && template.examples.length > 0) {
      prompt += '\n\n## Examples:\n';
      for (const example of template.examples) {
        prompt += this.formatExample(example);
      }
    }
    
    return prompt;
  }
  
  private validateContext(template: PromptTemplate, context: any) {
    for (const variable of template.variables) {
      if (variable.required && !(variable.name in context)) {
        throw new Error(`Required variable ${variable.name} not provided for template ${template.id}`);
      }
      
      if (variable.validator && variable.name in context) {
        if (!variable.validator(context[variable.name])) {
          throw new Error(`Variable ${variable.name} failed validation`);
        }
      }
    }
  }
  
  private formatValue(value: any, type: string): string {
    if (value === null || value === undefined) {
      return '';
    }
    
    switch (type) {
      case 'string':
        return String(value);
      case 'number':
        return String(value);
      case 'boolean':
        return value ? 'true' : 'false';
      case 'object':
      case 'array':
        // Pretty print objects and arrays
        if (typeof value === 'object') {
          return JSON.stringify(value, null, 2);
        }
        return String(value);
      default:
        return String(value);
    }
  }
  
  private formatExample(example: Example): string {
    let formatted = `\n### Example: ${example.description}\n`;
    formatted += '**Input:**\n';
    
    for (const [key, value] of Object.entries(example.input)) {
      formatted += `- ${key}: ${this.formatValue(value, typeof value)}\n`;
    }
    
    formatted += '\n**Output:**\n';
    formatted += example.output + '\n';
    
    return formatted;
  }
  
  async createTemplate(template: Omit<PromptTemplate, 'id'> | PromptTemplate): Promise<string> {
    const id = 'id' in template ? template.id : crypto.randomUUID();
    const fullTemplate: PromptTemplate = {
      ...template,
      id,
      metadata: {
        ...template.metadata,
        created: template.metadata.created || new Date(),
        modified: new Date()
      }
    };
    
    // Store in database
    this.db.run(
      `INSERT OR REPLACE INTO prompt_templates 
       (id, name, version, agent, template, variables, examples, metadata, created_at, modified_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        id,
        fullTemplate.name,
        fullTemplate.version,
        fullTemplate.agent,
        fullTemplate.template,
        JSON.stringify(fullTemplate.variables),
        fullTemplate.examples ? JSON.stringify(fullTemplate.examples) : null,
        JSON.stringify(fullTemplate.metadata),
        fullTemplate.metadata.created.getTime(),
        fullTemplate.metadata.modified.getTime()
      ]
    );
    
    // Cache in memory
    this.templates.set(id, fullTemplate);
    
    return id;
  }
  
  async updateTemplate(id: string, updates: Partial<PromptTemplate>) {
    const existing = this.templates.get(id);
    if (!existing) throw new Error(`Template ${id} not found`);
    
    const updated: PromptTemplate = {
      ...existing,
      ...updates,
      id, // Ensure ID doesn't change
      metadata: {
        ...existing.metadata,
        ...updates.metadata,
        modified: new Date()
      }
    };
    
    // Update database
    this.db.run(
      `UPDATE prompt_templates 
       SET name = ?, version = ?, template = ?, variables = ?, examples = ?, metadata = ?, modified_at = ?
       WHERE id = ?`,
      [
        updated.name,
        updated.version,
        updated.template,
        JSON.stringify(updated.variables),
        updated.examples ? JSON.stringify(updated.examples) : null,
        JSON.stringify(updated.metadata),
        updated.metadata.modified.getTime(),
        id
      ]
    );
    
    // Update cache
    this.templates.set(id, updated);
  }
  
  async forkTemplate(id: string, newVersion: string): Promise<string> {
    const existing = this.templates.get(id);
    if (!existing) throw new Error(`Template ${id} not found`);
    
    const forkedTemplate: PromptTemplate = {
      ...existing,
      id: `${existing.id}-${newVersion}`,
      version: newVersion,
      metadata: {
        ...existing.metadata,
        author: 'forked',
        created: new Date(),
        modified: new Date(),
        performance: undefined // Reset performance metrics
      }
    };
    
    return this.createTemplate(forkedTemplate);
  }
  
  async setActiveTemplate(agent: string, templateId: string) {
    // Verify template exists
    if (!this.templates.has(templateId)) {
      throw new Error(`Template ${templateId} not found`);
    }
    
    // Update active template
    this.activeTemplates.set(agent, templateId);
    
    // Persist to database
    this.db.run(
      `INSERT OR REPLACE INTO active_templates (agent, template_id, activated_at)
       VALUES (?, ?, ?)`,
      [agent, templateId, Date.now()]
    );
  }
  
  getActiveTemplate(agent: string): string | undefined {
    return this.activeTemplates.get(agent);
  }
  
  getAllTemplates(): PromptTemplate[] {
    return Array.from(this.templates.values());
  }
  
  getTemplatesByAgent(agent: string): PromptTemplate[] {
    return Array.from(this.templates.values())
      .filter(t => t.agent === agent);
  }
  
  async trackPerformance(
    templateId: string,
    metrics: {
      tokensUsed: number;
      duration: number;
      success: boolean;
    }
  ) {
    // Store performance data
    this.db.run(
      `INSERT INTO template_performance (template_id, tokens_used, duration, success, timestamp)
       VALUES (?, ?, ?, ?, ?)`,
      [
        templateId,
        metrics.tokensUsed,
        metrics.duration,
        metrics.success ? 1 : 0,
        Date.now()
      ]
    );
    
    // Update template performance metrics (rolling average)
    const template = this.templates.get(templateId);
    if (template && template.metadata.performance) {
      const perf = template.metadata.performance;
      
      // Simple exponential moving average
      perf.avgTokensUsed = perf.avgTokensUsed * 0.9 + metrics.tokensUsed * 0.1;
      perf.avgDuration = perf.avgDuration * 0.9 + metrics.duration * 0.1;
      perf.successRate = perf.successRate * 0.95 + (metrics.success ? 0.05 : 0);
      
      // Save updated metrics
      await this.updateTemplate(templateId, { metadata: template.metadata });
    }
  }
}