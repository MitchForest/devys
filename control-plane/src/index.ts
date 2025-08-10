import { Database } from 'bun:sqlite';
import { ContextMCPServer } from './mcp/context-mcp-server';
import { ModelMCPServer } from './mcp/model-mcp-server';
import { WorkflowModeController } from './workflow/workflow-mode-controller';
import { SlashCommandRegistry } from './claude/slash-commands';
import { HookManager } from './claude/hooks';

/**
 * Main entry point for the Control Plane application
 */
class ControlPlane {
  private db: Database;
  private contextServer: ContextMCPServer;
  private modelServer: ModelMCPServer;
  private workflowController: WorkflowModeController;
  private commandRegistry: SlashCommandRegistry;
  private hookManager: HookManager;
  private apiServer: any;
  
  constructor() {
    // Initialize database
    const dbPath = process.env.DATABASE_PATH || './control.db';
    this.db = new Database(dbPath);
    
    // Get configuration from environment
    const workspace = process.env.WORKSPACE_PATH || process.cwd();
    const contextPort = parseInt(process.env.MCP_CONTEXT_PORT || '9001');
    const modelPort = parseInt(process.env.MCP_MODEL_PORT || '9002');
    const apiPort = parseInt(process.env.API_PORT || '3000');
    
    // Initialize components
    this.contextServer = new ContextMCPServer(workspace, contextPort, this.db);
    this.modelServer = new ModelMCPServer(modelPort, this.db);
    this.workflowController = new WorkflowModeController(workspace, this.db);
    this.commandRegistry = new SlashCommandRegistry(workspace, this.db);
    this.hookManager = new HookManager(workspace, this.db);
    
    // Setup API server
    this.setupApiServer(apiPort);
  }
  
  /**
   * Setup HTTP API server
   */
  private setupApiServer(port: number) {
    this.apiServer = Bun.serve({
      port,
      
      async fetch(req, server) {
        const url = new URL(req.url);
        
        // Health check endpoint
        if (url.pathname === '/health') {
          return Response.json({
            status: 'healthy',
            timestamp: Date.now()
          });
        }
        
        // Ready check endpoint
        if (url.pathname === '/ready') {
          return Response.json({
            status: 'ready',
            services: {
              contextMCP: 'running',
              modelMCP: 'running',
              workflow: 'ready'
            }
          });
        }
        
        // Metrics endpoint
        if (url.pathname === '/metrics') {
          return Response.json({
            uptime: process.uptime(),
            memory: process.memoryUsage(),
            cpu: process.cpuUsage()
          });
        }
        
        // API routes
        if (url.pathname.startsWith('/api/')) {
          return handleApiRequest(req, url);
        }
        
        // WebSocket upgrade for real-time updates
        if (req.headers.get('upgrade') === 'websocket') {
          const success = server.upgrade(req);
          return success
            ? undefined
            : new Response('WebSocket upgrade failed', { status: 500 });
        }
        
        return new Response('Not Found', { status: 404 });
      },
      
      websocket: {
        open(ws) {
          console.log('WebSocket client connected');
          ws.send(JSON.stringify({ type: 'connected' }));
        },
        
        message(ws, message) {
          // Handle WebSocket messages
          try {
            const data = JSON.parse(message.toString());
            handleWebSocketMessage(ws, data);
          } catch (error) {
            ws.send(JSON.stringify({
              type: 'error',
              message: 'Invalid message format'
            }));
          }
        },
        
        close(ws) {
          console.log('WebSocket client disconnected');
        }
      }
    });
    
    console.log(`API server listening on port ${port}`);
  }
  
  /**
   * Start all services
   */
  async start() {
    console.log('Starting Control Plane...');
    
    try {
      // Start MCP servers
      await this.contextServer.start();
      console.log('✓ Context MCP server started');
      
      await this.modelServer.start();
      console.log('✓ Model MCP server started');
      
      // Initialize workflow controller
      await this.workflowController.initialize();
      console.log('✓ Workflow controller initialized');
      
      // Setup event listeners
      this.setupEventListeners();
      
      console.log('\n✨ Control Plane ready!');
      console.log(`   API: http://localhost:${process.env.API_PORT || 3000}`);
      console.log(`   Context MCP: localhost:${process.env.MCP_CONTEXT_PORT || 9001}`);
      console.log(`   Model MCP: localhost:${process.env.MCP_MODEL_PORT || 9002}`);
      
    } catch (error) {
      console.error('Failed to start Control Plane:', error);
      process.exit(1);
    }
  }
  
  /**
   * Setup event listeners for cross-component communication
   */
  private setupEventListeners() {
    // Listen for workflow events
    this.workflowController.on('workflow-started', (workflow) => {
      console.log(`Workflow started: ${workflow.id}`);
      this.broadcastEvent('workflow-started', workflow);
    });
    
    this.workflowController.on('workflow-completed', (workflow) => {
      console.log(`Workflow completed: ${workflow.id}`);
      this.broadcastEvent('workflow-completed', workflow);
    });
    
    // Listen for MCP events
    this.contextServer.on('context-updated', (data) => {
      this.broadcastEvent('context-updated', data);
    });
    
    this.modelServer.on('model-request', (data) => {
      this.broadcastEvent('model-request', data);
    });
    
    // Listen for hook events
    this.hookManager.on('hook-executed', (data) => {
      console.log(`Hook executed: ${data.hookId}`);
    });
  }
  
  /**
   * Broadcast event to WebSocket clients
   */
  private broadcastEvent(type: string, data: any) {
    // Would need to track WebSocket connections and broadcast
    // This is a placeholder for the actual implementation
    const message = JSON.stringify({ type, data, timestamp: Date.now() });
    console.log(`Broadcasting: ${type}`);
  }
  
  /**
   * Graceful shutdown
   */
  async shutdown() {
    console.log('\nShutting down Control Plane...');
    
    try {
      // Stop MCP servers
      await this.contextServer.stop();
      await this.modelServer.stop();
      
      // Close database
      this.db.close();
      
      // Stop API server
      if (this.apiServer) {
        this.apiServer.stop();
      }
      
      console.log('✓ Control Plane stopped');
      process.exit(0);
      
    } catch (error) {
      console.error('Error during shutdown:', error);
      process.exit(1);
    }
  }
}

/**
 * Handle API requests
 */
async function handleApiRequest(req: Request, url: URL): Promise<Response> {
  const path = url.pathname.replace('/api/', '');
  
  // Workflow endpoints
  if (path.startsWith('workflow/')) {
    return handleWorkflowRequest(req, path);
  }
  
  // Command endpoints
  if (path.startsWith('command/')) {
    return handleCommandRequest(req, path);
  }
  
  // Hook endpoints
  if (path.startsWith('hook/')) {
    return handleHookRequest(req, path);
  }
  
  return Response.json({ error: 'Unknown API endpoint' }, { status: 404 });
}

/**
 * Handle workflow API requests
 */
async function handleWorkflowRequest(req: Request, path: string): Promise<Response> {
  // Implementation would go here
  return Response.json({ message: 'Workflow API' });
}

/**
 * Handle command API requests
 */
async function handleCommandRequest(req: Request, path: string): Promise<Response> {
  // Implementation would go here
  return Response.json({ message: 'Command API' });
}

/**
 * Handle hook API requests
 */
async function handleHookRequest(req: Request, path: string): Promise<Response> {
  // Implementation would go here
  return Response.json({ message: 'Hook API' });
}

/**
 * Handle WebSocket messages
 */
function handleWebSocketMessage(ws: any, data: any) {
  switch (data.type) {
    case 'subscribe':
      // Subscribe to events
      ws.send(JSON.stringify({
        type: 'subscribed',
        events: data.events
      }));
      break;
      
    case 'command':
      // Execute command
      ws.send(JSON.stringify({
        type: 'command-result',
        result: 'Command executed'
      }));
      break;
      
    default:
      ws.send(JSON.stringify({
        type: 'error',
        message: `Unknown message type: ${data.type}`
      }));
  }
}

// Create and start the application
const app = new ControlPlane();

// Start the application
app.start().catch(console.error);

// Handle shutdown signals
process.on('SIGINT', () => app.shutdown());
process.on('SIGTERM', () => app.shutdown());

// Handle uncaught errors
process.on('uncaughtException', (error) => {
  console.error('Uncaught exception:', error);
  app.shutdown();
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled rejection at:', promise, 'reason:', reason);
  app.shutdown();
});

export default app;