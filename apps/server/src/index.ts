import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import filesRoute from './routes/files';
import { chatRoute } from './routes/chat';
import terminalRoute from './routes/terminal';
import { workflow } from './routes/workflow';
import { wsManager, type WSData } from './ws/websocket';

// Initialize server
const initializeServer = () => {
  // Claude Code uses its own authentication via 'claude setup-token'
  // No API key validation needed
  
  // eslint-disable-next-line no-console
  console.log('🚀 Starting devys Server');
  // eslint-disable-next-line no-console
  console.log('================================');
  // eslint-disable-next-line no-console
  console.log('🔐 Auth: Claude Code (via `claude setup-token`)');
  // eslint-disable-next-line no-console
  console.log('📊 Model: Configured in Claude Code');
  // eslint-disable-next-line no-console
  console.log('🔧 API: Claude Code SDK');
};

// Initialize on startup
initializeServer();

const app = new Hono();

// Middleware
app.use('*', cors({
  origin: ['http://localhost:5173', 'http://localhost:1420', 'tauri://localhost'],
  credentials: true
}));
app.use('*', logger());

// Routes
app.get('/', (c) => {
  return c.json({ 
    message: 'Claude Code IDE Server',
    version: '0.1.0',
    endpoints: {
      files: '/api/files/*',
      chat: '/api/chat',
      websocket: 'ws://localhost:3001/ws'
    }
  });
});

// Mount file routes
app.route('/api/files', filesRoute);

// Mount chat routes
app.route('/api/chat', chatRoute);

// Mount terminal routes
app.route('/api/terminal', terminalRoute);

// Mount workflow routes
app.route('/api/workflow', workflow);

// Health check
app.get('/health', (c) => {
  return c.json({ status: 'ok', timestamp: new Date().toISOString() });
});

const port = process.env.PORT || 3001;

// Create Bun server with both HTTP and WebSocket support
Bun.serve({
  port: Number(port),
  
  // Handle HTTP requests with Hono
  async fetch(req, server) {
    // Check if this is a WebSocket upgrade request
    if (server.upgrade(req)) {
      // upgrade() returns true if successful
      return; // Return undefined for successful upgrade
    }
    
    // Otherwise, handle as normal HTTP request with Hono
    return app.fetch(req);
  },
  
  // WebSocket handlers
  websocket: {
    open(ws) {
      wsManager.addConnection(ws);
    },
    
    message(ws, message) {
      wsManager.handleMessage(ws, message);
    },
    
    close(ws) {
      const data = ws.data as WSData | undefined;
      if (data?.connectionId) {
        wsManager.removeConnection(data.connectionId);
      }
    }
  }
});

// eslint-disable-next-line no-console
console.log(`🚀 Server running on http://localhost:${port}`);
// eslint-disable-next-line no-console
console.log(`🔌 WebSocket available at ws://localhost:${port}`);
// eslint-disable-next-line no-console
console.log(`📁 Working directory: ${process.cwd()}`);