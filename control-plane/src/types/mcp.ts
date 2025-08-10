// Model Context Protocol (MCP) type definitions

export interface MCPCapability {
  name: string;
  version: string;
  methods: string[];
  schema: any; // JSON Schema
}

export interface MCPRequest {
  id: string;
  method: string;
  params: any;
}

export interface MCPResponse {
  id: string;
  result?: any;
  error?: MCPError;
}

export interface MCPError {
  code: number;
  message: string;
  data?: any;
}

export interface MCPServerConfig {
  name: string;
  port: number;
  host?: string;
  enableAuth?: boolean;
  enableSSL?: boolean;
  maxConnections?: number;
  heartbeatInterval?: number;
}

export interface MCPConnection {
  id: string;
  clientId: string;
  connectedAt: number;
  lastActivity: number;
  capabilities: string[];
}

export interface MCPDiscoveryInfo {
  name: string;
  version: string;
  host: string;
  port: number;
  capabilities: MCPCapability[];
  status: 'online' | 'offline' | 'degraded';
  metrics?: MCPServerMetrics;
}

export interface MCPServerMetrics {
  uptime: number;
  requestsHandled: number;
  averageResponseTime: number;
  activeConnections: number;
  errorRate: number;
}

// Standard MCP error codes
export const MCPErrorCodes = {
  PARSE_ERROR: -32700,
  INVALID_REQUEST: -32600,
  METHOD_NOT_FOUND: -32601,
  INVALID_PARAMS: -32602,
  INTERNAL_ERROR: -32603,
  SERVER_ERROR: -32000,
  TIMEOUT: -32001,
  RATE_LIMIT: -32002,
  UNAUTHORIZED: -32003
} as const;

export type MCPErrorCode = typeof MCPErrorCodes[keyof typeof MCPErrorCodes];