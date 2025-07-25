import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import filesRoute from './routes/files';
import { chatRoute } from './routes/chat';
import terminalRoute from './routes/terminal';
import { wsManager, type WSData } from './ws/websocket';

// Validate required environment variables
const validateEnvironment = () => {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.error('❌ Missing required environment variable: ANTHROPIC_API_KEY');
    console.error('Please create a .env file with your Anthropic API key');
    console.error('See .env.example for reference');
    process.exit(1);
  }
  
  // eslint-disable-next-line no-console
  console.log('✅ Environment validated successfully');
  // eslint-disable-next-line no-console
  console.log(`📊 Model: ${process.env.CLAUDE_MODEL || 'sonnet'}`);
  // eslint-disable-next-line no-console
  console.log(`🌡️  Temperature: ${process.env.CLAUDE_TEMPERATURE || '0.7'}`);
};

// Validate on startup
validateEnvironment();

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