import { EventEmitter } from 'events';
import {
  MCPCapability,
  MCPRequest,
  MCPResponse,
  MCPError,
  MCPServerConfig,
  MCPConnection,
  MCPDiscoveryInfo,
  MCPServerMetrics,
  MCPErrorCodes
} from '../types/mcp';
import { Database } from 'bun:sqlite';

/**
 * Abstract base class for MCP servers following enterprise patterns
 * Implements connection management, request routing, and error handling
 */
export abstract class MCPServer extends EventEmitter {
  protected capabilities: MCPCapability[];
  protected server: any; // Bun.serve instance
  protected connections: Map<string, MCPConnection>;
  protected metrics: MCPServerMetrics;
  protected config: MCPServerConfig;
  protected db?: Database;
  private heartbeatTimer?: NodeJS.Timeout;
  private metricsTimer?: NodeJS.Timeout;
  
  constructor(config: MCPServerConfig, db?: Database) {
    super();
    this.config = {
      host: 'localhost',
      maxConnections: 100,
      heartbeatInterval: 30000,
      ...config
    };
    this.db = db;
    this.connections = new Map();
    this.capabilities = this.defineCapabilities();
    this.metrics = this.initializeMetrics();
    
    if (db) {
      this.initializeDatabase();
    }
  }
  
  /**
   * Define server capabilities - must be implemented by subclasses
   */
  abstract defineCapabilities(): MCPCapability[];
  
  /**
   * Handle incoming request - must be implemented by subclasses
   */
  abstract handleRequest(request: MCPRequest, connection: MCPConnection): Promise<MCPResponse>;
  
  /**
   * Initialize database tables for metrics and logging
   */
  private initializeDatabase() {
    if (!this.db) return;
    
    this.db.run(`
      CREATE TABLE IF NOT EXISTS mcp_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_name TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        method TEXT NOT NULL,
        params TEXT,
        response TEXT,
        duration INTEGER,
        success INTEGER,
        timestamp INTEGER NOT NULL
      )
    `);
    
    this.db.run(`
      CREATE TABLE IF NOT EXISTS mcp_connections (
        id TEXT PRIMARY KEY,
        server_name TEXT NOT NULL,
        client_id TEXT,
        connected_at INTEGER NOT NULL,
        disconnected_at INTEGER,
        requests_handled INTEGER DEFAULT 0
      )
    `);
  }
  
  /**
   * Initialize server metrics
   */
  private initializeMetrics(): MCPServerMetrics {
    return {
      uptime: 0,
      requestsHandled: 0,
      averageResponseTime: 0,
      activeConnections: 0,
      errorRate: 0
    };
  }
  
  /**
   * Start the MCP server
   */
  async start(): Promise<void> {
    try {
      this.server = Bun.serve({
        port: this.config.port,
        hostname: this.config.host,
        
        fetch: async (req, server) => {
          const url = new URL(req.url);
          
          // Handle WebSocket upgrade
          if (req.headers.get('upgrade') === 'websocket') {
            const connectionId = crypto.randomUUID();
            const success = server.upgrade(req, {
              data: { connectionId }
            });
            
            return success
              ? undefined
              : new Response('WebSocket upgrade failed', { status: 500 });
          }
          
          // Handle HTTP requests (for discovery and health checks)
          if (url.pathname === '/discovery') {
            return this.handleDiscoveryRequest();
          }
          
          if (url.pathname === '/health') {
            return this.handleHealthCheck();
          }
          
          if (url.pathname === '/metrics') {
            return this.handleMetricsRequest();
          }
          
          // Handle JSON-RPC over HTTP
          if (req.method === 'POST' && url.pathname === '/rpc') {
            return this.handleHttpRpcRequest(req);
          }
          
          return new Response('Not Found', { status: 404 });
        },
        
        websocket: {
          open: (ws) => this.handleWebSocketOpen(ws),
          message: (ws, message) => this.handleWebSocketMessage(ws, message),
          close: (ws) => this.handleWebSocketClose(ws),
          error: (ws, error) => this.handleWebSocketError(ws, error)
        }
      });
      
      console.log(`MCP Server ${this.config.name} listening on ${this.config.host}:${this.config.port}`);
      
      // Start heartbeat
      this.startHeartbeat();
      
      // Start metrics collection
      this.startMetricsCollection();
      
      this.emit('server-started', this.getDiscoveryInfo());
      
    } catch (error) {
      console.error(`Failed to start MCP server ${this.config.name}:`, error);
      throw error;
    }
  }
  
  /**
   * Stop the MCP server
   */
  async stop(): Promise<void> {
    // Stop timers
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
    }
    
    if (this.metricsTimer) {
      clearInterval(this.metricsTimer);
    }
    
    // Close all connections
    for (const connection of this.connections.values()) {
      this.closeConnection(connection.id);
    }
    
    // Stop server
    if (this.server) {
      this.server.stop();
    }
    
    this.emit('server-stopped');
    console.log(`MCP Server ${this.config.name} stopped`);
  }
  
  /**
   * Handle WebSocket connection open
   */
  private handleWebSocketOpen(ws: any) {
    const { connectionId } = ws.data;
    
    // Check connection limit
    if (this.connections.size >= this.config.maxConnections!) {
      ws.send(JSON.stringify({
        type: 'error',
        error: {
          code: MCPErrorCodes.SERVER_ERROR,
          message: 'Server at maximum capacity'
        }
      }));
      ws.close();
      return;
    }
    
    // Create connection record
    const connection: MCPConnection = {
      id: connectionId,
      clientId: 'unknown',
      connectedAt: Date.now(),
      lastActivity: Date.now(),
      capabilities: []
    };
    
    this.connections.set(connectionId, connection);
    this.metrics.activeConnections++;
    
    // Send capabilities
    ws.send(JSON.stringify({
      type: 'capabilities',
      capabilities: this.capabilities
    }));
    
    // Log connection
    if (this.db) {
      this.db.run(
        `INSERT INTO mcp_connections (id, server_name, connected_at)
         VALUES (?, ?, ?)`,
        [connectionId, this.config.name, connection.connectedAt]
      );
    }
    
    console.log(`Client connected to ${this.config.name}: ${connectionId}`);
    this.emit('client-connected', connection);
  }
  
  /**
   * Handle WebSocket message
   */
  private async handleWebSocketMessage(ws: any, message: any) {
    const { connectionId } = ws.data;
    const connection = this.connections.get(connectionId);
    
    if (!connection) {
      ws.send(JSON.stringify({
        type: 'error',
        error: {
          code: MCPErrorCodes.UNAUTHORIZED,
          message: 'Connection not registered'
        }
      }));
      return;
    }
    
    connection.lastActivity = Date.now();
    
    try {
      const data = typeof message === 'string' 
        ? JSON.parse(message)
        : JSON.parse(new TextDecoder().decode(message));
      
      // Handle different message types
      if (data.type === 'request') {
        await this.processRequest(ws, data, connection);
      } else if (data.type === 'ping') {
        ws.send(JSON.stringify({ type: 'pong' }));
      } else if (data.type === 'identify') {
        connection.clientId = data.clientId;
        connection.capabilities = data.capabilities || [];
      }
      
    } catch (error) {
      console.error(`Error processing message from ${connectionId}:`, error);
      
      ws.send(JSON.stringify({
        type: 'error',
        error: {
          code: MCPErrorCodes.PARSE_ERROR,
          message: 'Invalid message format'
        }
      }));
    }
  }
  
  /**
   * Handle WebSocket close
   */
  private handleWebSocketClose(ws: any) {
    const { connectionId } = ws.data;
    this.closeConnection(connectionId);
  }
  
  /**
   * Handle WebSocket error
   */
  private handleWebSocketError(ws: any, error: any) {
    const { connectionId } = ws.data;
    console.error(`WebSocket error for ${connectionId}:`, error);
    this.closeConnection(connectionId);
  }
  
  /**
   * Process incoming request
   */
  private async processRequest(ws: any, data: any, connection: MCPConnection) {
    const startTime = Date.now();
    const request: MCPRequest = {
      id: data.id || crypto.randomUUID(),
      method: data.method,
      params: data.params
    };
    
    let response: MCPResponse;
    let success = true;
    
    try {
      // Validate request
      if (!request.method) {
        throw this.createError(MCPErrorCodes.INVALID_REQUEST, 'Method is required');
      }
      
      // Handle request
      response = await this.handleRequest(request, connection);
      
      // Update metrics
      this.metrics.requestsHandled++;
      
    } catch (error) {
      success = false;
      response = {
        id: request.id,
        error: error.code ? error : {
          code: MCPErrorCodes.INTERNAL_ERROR,
          message: error.message || 'Internal server error'
        }
      };
      
      // Update error rate
      this.updateErrorRate(false);
    }
    
    // Send response
    ws.send(JSON.stringify({
      type: 'response',
      ...response
    }));
    
    // Log request
    const duration = Date.now() - startTime;
    this.updateAverageResponseTime(duration);
    
    if (this.db) {
      this.db.run(
        `INSERT INTO mcp_requests 
         (server_name, connection_id, method, params, response, duration, success, timestamp)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          this.config.name,
          connection.id,
          request.method,
          JSON.stringify(request.params),
          JSON.stringify(response),
          duration,
          success ? 1 : 0,
          Date.now()
        ]
      );
    }
    
    this.emit('request-handled', {
      request,
      response,
      duration,
      connection
    });
  }
  
  /**
   * Handle HTTP RPC request
   */
  private async handleHttpRpcRequest(req: Request): Promise<Response> {
    try {
      const data = await req.json();
      
      const request: MCPRequest = {
        id: data.id || crypto.randomUUID(),
        method: data.method,
        params: data.params
      };
      
      // Create temporary connection for HTTP request
      const connection: MCPConnection = {
        id: 'http-' + crypto.randomUUID(),
        clientId: 'http-client',
        connectedAt: Date.now(),
        lastActivity: Date.now(),
        capabilities: []
      };
      
      const response = await this.handleRequest(request, connection);
      
      return Response.json(response);
      
    } catch (error) {
      return Response.json({
        id: null,
        error: {
          code: MCPErrorCodes.PARSE_ERROR,
          message: 'Invalid request'
        }
      }, { status: 400 });
    }
  }
  
  /**
   * Handle discovery request
   */
  private handleDiscoveryRequest(): Response {
    return Response.json(this.getDiscoveryInfo());
  }
  
  /**
   * Handle health check
   */
  private handleHealthCheck(): Response {
    const healthy = this.connections.size < this.config.maxConnections! &&
                   this.metrics.errorRate < 0.5;
    
    return Response.json({
      status: healthy ? 'healthy' : 'degraded',
      uptime: this.metrics.uptime,
      connections: this.connections.size,
      errorRate: this.metrics.errorRate
    }, {
      status: healthy ? 200 : 503
    });
  }
  
  /**
   * Handle metrics request
   */
  private handleMetricsRequest(): Response {
    return Response.json(this.metrics);
  }
  
  /**
   * Get discovery information
   */
  getDiscoveryInfo(): MCPDiscoveryInfo {
    return {
      name: this.config.name,
      version: '1.0.0',
      host: this.config.host!,
      port: this.config.port,
      capabilities: this.capabilities,
      status: this.getServerStatus(),
      metrics: this.metrics
    };
  }
  
  /**
   * Get server status
   */
  private getServerStatus(): 'online' | 'offline' | 'degraded' {
    if (!this.server) return 'offline';
    if (this.metrics.errorRate > 0.5) return 'degraded';
    if (this.connections.size >= this.config.maxConnections!) return 'degraded';
    return 'online';
  }
  
  /**
   * Close a connection
   */
  private closeConnection(connectionId: string) {
    const connection = this.connections.get(connectionId);
    if (!connection) return;
    
    this.connections.delete(connectionId);
    this.metrics.activeConnections--;
    
    // Log disconnection
    if (this.db) {
      this.db.run(
        `UPDATE mcp_connections 
         SET disconnected_at = ?
         WHERE id = ?`,
        [Date.now(), connectionId]
      );
    }
    
    console.log(`Client disconnected from ${this.config.name}: ${connectionId}`);
    this.emit('client-disconnected', connection);
  }
  
  /**
   * Start heartbeat timer
   */
  private startHeartbeat() {
    this.heartbeatTimer = setInterval(() => {
      const now = Date.now();
      
      // Check for stale connections
      for (const [id, connection] of this.connections) {
        if (now - connection.lastActivity > this.config.heartbeatInterval! * 2) {
          console.log(`Removing stale connection: ${id}`);
          this.closeConnection(id);
        }
      }
      
      // Update uptime
      this.metrics.uptime += this.config.heartbeatInterval!;
      
    }, this.config.heartbeatInterval);
  }
  
  /**
   * Start metrics collection
   */
  private startMetricsCollection() {
    this.metricsTimer = setInterval(() => {
      this.emit('metrics-update', this.metrics);
      
      // Reset some metrics
      this.metrics.errorRate = 0;
      
    }, 60000); // Every minute
  }
  
  /**
   * Update average response time
   */
  private updateAverageResponseTime(duration: number) {
    const count = this.metrics.requestsHandled;
    const current = this.metrics.averageResponseTime;
    
    this.metrics.averageResponseTime = (current * (count - 1) + duration) / count;
  }
  
  /**
   * Update error rate
   */
  private updateErrorRate(success: boolean) {
    const alpha = 0.1; // Exponential moving average factor
    const value = success ? 0 : 1;
    
    this.metrics.errorRate = this.metrics.errorRate * (1 - alpha) + value * alpha;
  }
  
  /**
   * Create MCP error
   */
  protected createError(code: number, message: string, data?: any): MCPError {
    return { code, message, data };
  }
  
  /**
   * Broadcast to all connections
   */
  protected broadcast(message: any) {
    const data = JSON.stringify(message);
    
    for (const connection of this.connections.values()) {
      // Would need WebSocket reference tracking for actual broadcast
      console.log(`Would broadcast to ${connection.id}: ${data}`);
    }
  }
}