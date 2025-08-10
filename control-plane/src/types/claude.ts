export interface SlashCommand {
  name: string;
  description: string;
  aliases: string[];
  parameters: CommandParameter[];
  handler: (params: CommandParams) => Promise<any>;
  permissions: string[];
}

export interface CommandParameter {
  name: string;
  type: 'string' | 'number' | 'boolean' | 'array' | 'object';
  required: boolean;
  default?: any;
  description?: string;
  choices?: string[];
}

export interface CommandParams {
  command: string;
  args: Record<string, any>;
  sessionId: string;
  workflowId?: string;
  userId?: string;
}

export interface Hook {
  id: string;
  type: 'pre' | 'post';
  event: string;
  handler: (context: HookContext) => Promise<HookResult>;
  priority: number;
  enabled: boolean;
}

export interface HookContext {
  event: string;
  data: any;
  session: SessionContext;
  cancel?: () => void;
  modify?: (data: any) => void;
}

export interface SessionContext {
  sessionId: string;
  userId?: string;
  workspace: string;
  workflowId?: string;
}

export interface HookResult {
  continue: boolean;
  modifiedData?: any;
  message?: string;
}