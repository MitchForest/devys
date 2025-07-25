import { Hono } from 'hono';
import { z } from 'zod';
import { zValidator } from '@hono/zod-validator';
import { spawn, type ChildProcess } from 'child_process';
import * as os from 'os';

const terminalRoute = new Hono();

// Schema for terminal commands
const ExecuteCommandSchema = z.object({
  sessionId: z.string(),
  command: z.string(),
  cwd: z.string().optional(),
  env: z.record(z.string()).optional()
});

// Store active terminal sessions
const sessions = new Map<string, {
  process: ChildProcess | null;
  cwd: string;
  history: string[];
}>();

// Execute command endpoint
terminalRoute.post('/execute', zValidator('json', ExecuteCommandSchema), async (c) => {
  const { sessionId, command, cwd, env } = c.req.valid('json');
  
  try {
    // Get or create session
    let session = sessions.get(sessionId);
    if (!session) {
      session = {
        process: null,
        cwd: cwd || process.cwd(),
        history: []
      };
      sessions.set(sessionId, session);
    }
    
    // Update cwd if provided
    if (cwd) {
      session.cwd = cwd;
    }
    
    // Add to history
    session.history.push(command);
    
    // Parse command and arguments
    const [cmd, ...args] = parseCommand(command);
    
    // Handle built-in commands
    if (cmd === 'cd') {
      const newDir = args[0] || os.homedir();
      try {
        process.chdir(newDir);
        session.cwd = process.cwd();
        return c.json({ 
          output: '', 
          error: '',
          cwd: session.cwd 
        });
      } catch (error) {
        return c.json({ 
          output: '', 
          error: `cd: ${error instanceof Error ? error.message : 'Unknown error'}`,
          cwd: session.cwd 
        });
      }
    }
    
    // Execute command
    return new Promise((resolve) => {
      const proc = spawn(cmd, args, {
        cwd: session!.cwd,
        env: { ...process.env, ...env },
        shell: true
      });
      
      let output = '';
      let error = '';
      
      proc.stdout.on('data', (data) => {
        output += data.toString();
      });
      
      proc.stderr.on('data', (data) => {
        error += data.toString();
      });
      
      proc.on('close', (code) => {
        resolve(c.json({
          output,
          error,
          exitCode: code,
          cwd: session!.cwd
        }));
      });
      
      proc.on('error', (err) => {
        resolve(c.json({
          output: '',
          error: err.message,
          exitCode: -1,
          cwd: session!.cwd
        }));
      });
      
      // Store process reference
      session!.process = proc;
      
      // Kill process after timeout (30 seconds)
      setTimeout(() => {
        if (proc.exitCode === null) {
          proc.kill();
        }
      }, 30000);
    });
  } catch (error) {
    return c.json({ 
      error: error instanceof Error ? error.message : 'Command execution failed',
      output: '',
      exitCode: -1
    }, 500);
  }
});

// Kill session endpoint
terminalRoute.post('/kill/:sessionId', (c) => {
  const sessionId = c.req.param('sessionId');
  const session = sessions.get(sessionId);
  
  if (session?.process) {
    session.process.kill();
    sessions.delete(sessionId);
    return c.json({ success: true });
  }
  
  return c.json({ error: 'Session not found' }, 404);
});

// Get session info
terminalRoute.get('/session/:sessionId', (c) => {
  const sessionId = c.req.param('sessionId');
  const session = sessions.get(sessionId);
  
  if (!session) {
    return c.json({ error: 'Session not found' }, 404);
  }
  
  return c.json({
    sessionId,
    cwd: session.cwd,
    history: session.history,
    isActive: session.process !== null && session.process.exitCode === null
  });
});

// List all sessions
terminalRoute.get('/sessions', (c) => {
  const sessionList = Array.from(sessions.entries()).map(([id, session]) => ({
    sessionId: id,
    cwd: session.cwd,
    historyLength: session.history.length,
    isActive: session.process !== null && session.process.exitCode === null
  }));
  
  return c.json({ sessions: sessionList });
});

// Helper function to parse command line
function parseCommand(commandLine: string): string[] {
  const args: string[] = [];
  let current = '';
  let inQuote = false;
  let quoteChar = '';
  let escaped = false;
  
  for (let i = 0; i < commandLine.length; i++) {
    const char = commandLine[i];
    
    if (escaped) {
      current += char;
      escaped = false;
      continue;
    }
    
    if (char === '\\') {
      escaped = true;
      continue;
    }
    
    if ((char === '"' || char === "'") && !inQuote) {
      inQuote = true;
      quoteChar = char;
      continue;
    }
    
    if (char === quoteChar && inQuote) {
      inQuote = false;
      quoteChar = '';
      continue;
    }
    
    if (char === ' ' && !inQuote) {
      if (current) {
        args.push(current);
        current = '';
      }
      continue;
    }
    
    current += char;
  }
  
  if (current) {
    args.push(current);
  }
  
  return args;
}

export default terminalRoute;