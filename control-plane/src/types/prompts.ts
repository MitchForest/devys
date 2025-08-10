export interface PromptTemplate {
  id: string;
  name: string;
  version: string;
  agent: 'planner' | 'editor' | 'reviewer' | 'grunt';
  template: string;
  variables: VariableDefinition[];
  examples?: Example[];
  metadata: {
    author: string;
    created: Date;
    modified: Date;
    performance?: PerformanceMetrics;
  };
}

export interface VariableDefinition {
  name: string;
  type: 'string' | 'number' | 'boolean' | 'object' | 'array';
  required: boolean;
  default?: any;
  description: string;
  validator?: (value: any) => boolean;
}

export interface Example {
  description: string;
  input: Record<string, any>;
  output: string;
}

export interface PerformanceMetrics {
  avgTokensUsed: number;
  avgDuration: number;
  successRate: number;
}

export interface ComparisonResult {
  templateA: string;
  templateB: string;
  winner: string;
  metrics: {
    avgTokensA: number;
    avgTokensB: number;
    avgDurationA: number;
    avgDurationB: number;
    successRateA: number;
    successRateB: number;
  };
  recommendation: string;
}