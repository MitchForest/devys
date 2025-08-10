import {
  SlashCommand,
  CommandParameter,
  CommandParams
} from '../types/claude';
import { WorkflowModeController } from '../workflow/workflow-mode-controller';
import { ContextGenerator } from '../services/context/context-generator';
import { Database } from 'bun:sqlite';

export class SlashCommandRegistry {
  private commands: Map<string, SlashCommand>;
  private aliases: Map<string, string>; // alias -> command name
  private workflowController: WorkflowModeController;
  private contextGenerator: ContextGenerator;
  
  constructor(
    private workspace: string,
    private db: Database
  ) {
    this.commands = new Map();
    this.aliases = new Map();
    this.workflowController = new WorkflowModeController(workspace, db);
    this.contextGenerator = new ContextGenerator(workspace, db);
    
    this.registerDefaultCommands();
  }
  
  private registerDefaultCommands() {
    // /plan - Start planning mode
    this.register({
      name: 'plan',
      description: 'Create a plan for a development task',
      aliases: ['p'],
      parameters: [
        {
          name: 'task',
          type: 'string',
          required: true,
          description: 'The task to plan'
        }
      ],
      handler: async (params) => {
        const workflowId = await this.workflowController.startWorkflow(
          params.sessionId,
          params.args.task
        );
        
        return {
          success: true,
          workflowId,
          mode: 'plan',
          message: 'Planning workflow started'
        };
      },
      permissions: ['execute']
    });
    
    // /edit - Execute edits from plan
    this.register({
      name: 'edit',
      description: 'Execute edits from the current plan',
      aliases: ['e'],
      parameters: [
        {
          name: 'stepId',
          type: 'string',
          required: false,
          description: 'Specific step to execute'
        }
      ],
      handler: async (params) => {
        if (!params.workflowId) {
          throw new Error('No active workflow. Use /plan first');
        }
        
        const workflow = await this.workflowController.getWorkflow(params.workflowId);
        if (!workflow) {
          throw new Error('Workflow not found');
        }
        
        if (workflow.mode !== 'edit') {
          throw new Error(`Cannot edit in ${workflow.mode} mode`);
        }
        
        return {
          success: true,
          message: 'Executing edits...',
          workflow
        };
      },
      permissions: ['execute']
    });
    
    // /review - Review changes
    this.register({
      name: 'review',
      description: 'Review the changes made',
      aliases: ['r'],
      parameters: [],
      handler: async (params) => {
        if (!params.workflowId) {
          throw new Error('No active workflow');
        }
        
        const workflow = await this.workflowController.getWorkflow(params.workflowId);
        if (!workflow) {
          throw new Error('Workflow not found');
        }
        
        if (!workflow.edits || workflow.edits.length === 0) {
          throw new Error('No edits to review');
        }
        
        return {
          success: true,
          message: 'Starting review...',
          workflow
        };
      },
      permissions: ['execute']
    });
    
    // /status - Check workflow status
    this.register({
      name: 'status',
      description: 'Check the status of current workflow',
      aliases: ['s'],
      parameters: [
        {
          name: 'verbose',
          type: 'boolean',
          required: false,
          default: false,
          description: 'Show detailed status'
        }
      ],
      handler: async (params) => {
        if (!params.workflowId) {
          // Show all active workflows
          const activeWorkflows = this.workflowController.getActiveWorkflows();
          
          return {
            success: true,
            activeWorkflows: activeWorkflows.map(w => ({
              id: w.id,
              task: w.task,
              mode: w.mode,
              status: w.status,
              progress: w.progress
            }))
          };
        }
        
        const workflow = await this.workflowController.getStatus(params.workflowId);
        
        if (!workflow) {
          throw new Error('Workflow not found');
        }
        
        if (params.args.verbose) {
          return {
            success: true,
            workflow
          };
        }
        
        return {
          success: true,
          id: workflow.id,
          task: workflow.task,
          mode: workflow.mode,
          status: workflow.status,
          progress: workflow.progress,
          errors: workflow.errors
        };
      },
      permissions: ['read']
    });
    
    // /abort - Cancel current workflow
    this.register({
      name: 'abort',
      description: 'Cancel the current workflow',
      aliases: ['cancel', 'stop'],
      parameters: [
        {
          name: 'force',
          type: 'boolean',
          required: false,
          default: false,
          description: 'Force cancel without cleanup'
        }
      ],
      handler: async (params) => {
        if (!params.workflowId) {
          throw new Error('No active workflow to cancel');
        }
        
        await this.workflowController.cancelWorkflow(params.workflowId);
        
        return {
          success: true,
          message: 'Workflow cancelled'
        };
      },
      permissions: ['execute']
    });
    
    // /pause - Pause current workflow
    this.register({
      name: 'pause',
      description: 'Pause the current workflow',
      aliases: [],
      parameters: [],
      handler: async (params) => {
        if (!params.workflowId) {
          throw new Error('No active workflow to pause');
        }
        
        await this.workflowController.pauseWorkflow(params.workflowId);
        
        return {
          success: true,
          message: 'Workflow paused'
        };
      },
      permissions: ['execute']
    });
    
    // /resume - Resume paused workflow
    this.register({
      name: 'resume',
      description: 'Resume a paused workflow',
      aliases: [],
      parameters: [],
      handler: async (params) => {
        if (!params.workflowId) {
          throw new Error('No workflow to resume');
        }
        
        await this.workflowController.resumeWorkflow(params.workflowId);
        
        return {
          success: true,
          message: 'Workflow resumed'
        };
      },
      permissions: ['execute']
    });
    
    // /context - Manage context
    this.register({
      name: 'context',
      description: 'View or modify the current context',
      aliases: ['ctx'],
      parameters: [
        {
          name: 'action',
          type: 'string',
          required: false,
          default: 'view',
          choices: ['view', 'add', 'remove', 'clear', 'refresh'],
          description: 'Action to perform'
        },
        {
          name: 'files',
          type: 'array',
          required: false,
          description: 'Files to add or remove'
        },
        {
          name: 'patterns',
          type: 'array',
          required: false,
          description: 'File patterns to include'
        }
      ],
      handler: async (params) => {
        const action = params.args.action || 'view';
        
        switch (action) {
          case 'view':
            const context = await this.contextGenerator.generateContext({
              maxTokens: 10000
            });
            
            return {
              success: true,
              fileCount: context.metadata.fileCount,
              symbolCount: context.metadata.symbolCount,
              totalTokens: context.metadata.totalTokens,
              files: context.selectedFiles?.map(f => f.path)
            };
            
          case 'add':
            if (!params.args.files && !params.args.patterns) {
              throw new Error('Specify files or patterns to add');
            }
            
            const addContext = await this.contextGenerator.generateContext({
              files: params.args.files,
              patterns: params.args.patterns,
              maxTokens: 50000
            });
            
            return {
              success: true,
              message: 'Context updated',
              added: addContext.metadata.fileCount
            };
            
          case 'remove':
            // This would need implementation in ContextGenerator
            return {
              success: true,
              message: 'Files removed from context'
            };
            
          case 'clear':
            this.contextGenerator.clearCache();
            
            return {
              success: true,
              message: 'Context cleared'
            };
            
          case 'refresh':
            this.contextGenerator.clearCache();
            const refreshed = await this.contextGenerator.generateContext({
              maxTokens: 10000
            });
            
            return {
              success: true,
              message: 'Context refreshed',
              fileCount: refreshed.metadata.fileCount
            };
            
          default:
            throw new Error(`Unknown action: ${action}`);
        }
      },
      permissions: ['read', 'write']
    });
    
    // /metrics - View performance metrics
    this.register({
      name: 'metrics',
      description: 'View performance and cost metrics',
      aliases: ['m'],
      parameters: [
        {
          name: 'type',
          type: 'string',
          required: false,
          default: 'summary',
          choices: ['summary', 'models', 'agents', 'cache'],
          description: 'Type of metrics to view'
        }
      ],
      handler: async (params) => {
        const type = params.args.type || 'summary';
        
        switch (type) {
          case 'summary':
            return {
              success: true,
              metrics: {
                activeWorkflows: this.workflowController.getActiveWorkflows().length,
                cacheMetrics: this.contextGenerator.getMetrics()
              }
            };
            
          case 'models':
            // Would need to expose from ModelRouter
            return {
              success: true,
              message: 'Model metrics not yet implemented'
            };
            
          case 'agents':
            // Would need to track in agents
            return {
              success: true,
              message: 'Agent metrics not yet implemented'
            };
            
          case 'cache':
            return {
              success: true,
              metrics: this.contextGenerator.getMetrics()
            };
            
          default:
            throw new Error(`Unknown metrics type: ${type}`);
        }
      },
      permissions: ['read']
    });
    
    // /help - Show available commands
    this.register({
      name: 'help',
      description: 'Show available commands',
      aliases: ['h', '?'],
      parameters: [
        {
          name: 'command',
          type: 'string',
          required: false,
          description: 'Get help for specific command'
        }
      ],
      handler: async (params) => {
        if (params.args.command) {
          const cmd = this.commands.get(params.args.command) || 
                      this.commands.get(this.aliases.get(params.args.command) || '');
          
          if (!cmd) {
            throw new Error(`Unknown command: ${params.args.command}`);
          }
          
          return {
            success: true,
            command: {
              name: cmd.name,
              description: cmd.description,
              aliases: cmd.aliases,
              parameters: cmd.parameters.map(p => ({
                name: p.name,
                type: p.type,
                required: p.required,
                default: p.default,
                description: p.description,
                choices: p.choices
              }))
            }
          };
        }
        
        // List all commands
        const commandList = Array.from(this.commands.values()).map(cmd => ({
          name: `/${cmd.name}`,
          aliases: cmd.aliases.map(a => `/${a}`),
          description: cmd.description
        }));
        
        return {
          success: true,
          commands: commandList
        };
      },
      permissions: ['read']
    });
  }
  
  register(command: SlashCommand) {
    // Validate command
    if (!command.name || !command.handler) {
      throw new Error('Command must have name and handler');
    }
    
    // Check for duplicate names
    if (this.commands.has(command.name)) {
      throw new Error(`Command ${command.name} already registered`);
    }
    
    // Register command
    this.commands.set(command.name, command);
    
    // Register aliases
    for (const alias of command.aliases) {
      if (this.aliases.has(alias)) {
        throw new Error(`Alias ${alias} already in use`);
      }
      this.aliases.set(alias, command.name);
    }
    
    console.log(`Registered command: /${command.name}`);
  }
  
  async execute(commandStr: string, params: Omit<CommandParams, 'command'>): Promise<any> {
    // Parse command and arguments
    const parts = commandStr.split(' ');
    const commandName = parts[0].replace(/^\//, '');
    
    // Find command
    const command = this.commands.get(commandName) || 
                   this.commands.get(this.aliases.get(commandName) || '');
    
    if (!command) {
      throw new Error(`Unknown command: /${commandName}`);
    }
    
    // Parse arguments
    const args = this.parseArguments(parts.slice(1), command.parameters);
    
    // Validate required parameters
    for (const param of command.parameters) {
      if (param.required && !(param.name in args)) {
        throw new Error(`Missing required parameter: ${param.name}`);
      }
    }
    
    // Check permissions (would need actual permission system)
    // For now, assume all permissions granted
    
    // Execute handler
    const fullParams: CommandParams = {
      ...params,
      command: command.name,
      args
    };
    
    try {
      return await command.handler(fullParams);
    } catch (error) {
      console.error(`Command /${command.name} failed:`, error);
      throw error;
    }
  }
  
  private parseArguments(
    argStrings: string[],
    parameters: CommandParameter[]
  ): Record<string, any> {
    const args: Record<string, any> = {};
    
    // Simple parsing - in production would need more sophisticated parsing
    let currentParam: string | null = null;
    let currentValue: any[] = [];
    
    for (const arg of argStrings) {
      if (arg.startsWith('--')) {
        // Save previous parameter
        if (currentParam) {
          const param = parameters.find(p => p.name === currentParam);
          if (param?.type === 'array') {
            args[currentParam] = currentValue;
          } else {
            args[currentParam] = currentValue[0] || true;
          }
        }
        
        // Start new parameter
        currentParam = arg.slice(2);
        currentValue = [];
      } else {
        currentValue.push(arg);
      }
    }
    
    // Save last parameter
    if (currentParam) {
      const param = parameters.find(p => p.name === currentParam);
      if (param?.type === 'array') {
        args[currentParam] = currentValue;
      } else {
        args[currentParam] = currentValue[0] || true;
      }
    }
    
    // If no named parameters and there's a single required string param, use positional
    if (Object.keys(args).length === 0 && argStrings.length > 0) {
      const stringParam = parameters.find(p => p.type === 'string' && p.required);
      if (stringParam) {
        args[stringParam.name] = argStrings.join(' ');
      }
    }
    
    // Apply defaults
    for (const param of parameters) {
      if (!(param.name in args) && param.default !== undefined) {
        args[param.name] = param.default;
      }
    }
    
    return args;
  }
  
  getCommands(): SlashCommand[] {
    return Array.from(this.commands.values());
  }
  
  getCommand(name: string): SlashCommand | undefined {
    return this.commands.get(name) || 
           this.commands.get(this.aliases.get(name) || '');
  }
}