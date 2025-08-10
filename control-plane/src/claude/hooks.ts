import {
  Hook,
  HookContext,
  HookResult,
  SessionContext
} from '../types/claude';
import { $ } from 'bun';
import { Database } from 'bun:sqlite';

export class HookManager {
  private hooks: Map<string, Hook[]>;
  private db: Database;
  
  constructor(
    private workspace: string,
    db: Database
  ) {
    this.hooks = new Map();
    this.db = db;
    
    this.initializeDatabase();
    this.registerDefaultHooks();
    this.loadUserHooks();
  }
  
  private initializeDatabase() {
    this.db.run(`
      CREATE TABLE IF NOT EXISTS hooks (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        event TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        handler TEXT NOT NULL,
        priority INTEGER DEFAULT 0,
        enabled INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    `);
    
    this.db.run(`
      CREATE TABLE IF NOT EXISTS hook_executions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hook_id TEXT NOT NULL,
        event TEXT NOT NULL,
        success INTEGER NOT NULL,
        duration INTEGER,
        error TEXT,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (hook_id) REFERENCES hooks(id)
      )
    `);
  }
  
  private registerDefaultHooks() {
    // Pre-edit validation hook
    this.register({
      id: 'validate-edit',
      type: 'pre',
      event: 'edit',
      priority: 10,
      enabled: true,
      handler: async (context) => {
        // Validate that files exist and are writable
        const files = context.data.files || [];
        const errors: string[] = [];
        
        for (const file of files) {
          const fullPath = `${this.workspace}/${file}`;
          const fileObj = Bun.file(fullPath);
          
          // Check if file exists (for edit operations)
          if (context.data.operation === 'edit' && !await fileObj.exists()) {
            errors.push(`File ${file} does not exist`);
          }
          
          // Check if parent directory exists (for create operations)
          if (context.data.operation === 'create') {
            const dir = fullPath.substring(0, fullPath.lastIndexOf('/'));
            try {
              await $`test -d ${dir}`.quiet();
            } catch {
              errors.push(`Directory for ${file} does not exist`);
            }
          }
        }
        
        if (errors.length > 0) {
          return {
            continue: false,
            message: `Validation failed: ${errors.join(', ')}`
          };
        }
        
        return { continue: true };
      }
    });
    
    // Post-edit testing hook
    this.register({
      id: 'run-tests',
      type: 'post',
      event: 'edit',
      priority: 5,
      enabled: true,
      handler: async (context) => {
        // Run tests for affected files
        const files = context.data.files || [];
        
        // Skip if no test runner configured
        const packageJson = Bun.file(`${this.workspace}/package.json`);
        if (!await packageJson.exists()) {
          return { continue: true };
        }
        
        const pkg = await packageJson.json();
        if (!pkg.scripts?.test) {
          return { continue: true };
        }
        
        // Run tests
        try {
          const result = await $`cd ${this.workspace} && npm test`.quiet();
          
          return {
            continue: true,
            message: 'Tests passed'
          };
        } catch (error) {
          return {
            continue: true,
            message: `Warning: Tests failed - ${error}`
          };
        }
      }
    });
    
    // Pre-commit validation hook
    this.register({
      id: 'pre-commit',
      type: 'pre',
      event: 'commit',
      priority: 20,
      enabled: true,
      handler: async (context) => {
        const files = context.data.files || [];
        
        // Run linting
        const lintErrors: string[] = [];
        
        for (const file of files) {
          const ext = file.split('.').pop()?.toLowerCase();
          
          if (ext === 'ts' || ext === 'tsx' || ext === 'js' || ext === 'jsx') {
            try {
              await $`npx eslint ${this.workspace}/${file} --fix`.quiet();
              
              // File was auto-fixed
              context.modify?.({
                ...context.data,
                filesFixed: [...(context.data.filesFixed || []), file]
              });
            } catch (error) {
              lintErrors.push(`${file}: Linting failed`);
            }
          }
        }
        
        if (lintErrors.length > 0) {
          return {
            continue: false,
            message: `Linting errors: ${lintErrors.join(', ')}`
          };
        }
        
        return { continue: true };
      }
    });
    
    // Post-commit notification hook
    this.register({
      id: 'post-commit',
      type: 'post',
      event: 'commit',
      priority: 1,
      enabled: true,
      handler: async (context) => {
        const commitHash = context.data.commitHash;
        const message = context.data.message;
        
        console.log(`✅ Commit successful: ${commitHash}`);
        console.log(`   Message: ${message}`);
        
        return {
          continue: true,
          message: `Committed: ${commitHash}`
        };
      }
    });
    
    // Pre-deploy validation hook
    this.register({
      id: 'pre-deploy',
      type: 'pre',
      event: 'deploy',
      priority: 30,
      enabled: true,
      handler: async (context) => {
        // Check for uncommitted changes
        try {
          const status = await $`cd ${this.workspace} && git status --porcelain`.quiet();
          
          if (status.stdout) {
            return {
              continue: false,
              message: 'Uncommitted changes detected. Please commit before deploying.'
            };
          }
        } catch (error) {
          // Git not available or not a git repo
        }
        
        // Run build
        const packageJson = Bun.file(`${this.workspace}/package.json`);
        if (await packageJson.exists()) {
          const pkg = await packageJson.json();
          
          if (pkg.scripts?.build) {
            try {
              await $`cd ${this.workspace} && npm run build`.quiet();
            } catch (error) {
              return {
                continue: false,
                message: `Build failed: ${error}`
              };
            }
          }
        }
        
        return { continue: true };
      }
    });
    
    // File size check hook
    this.register({
      id: 'file-size-check',
      type: 'pre',
      event: 'edit',
      priority: 5,
      enabled: true,
      handler: async (context) => {
        const maxFileSize = 10 * 1024 * 1024; // 10MB
        const files = context.data.files || [];
        const largeFiles: string[] = [];
        
        for (const file of files) {
          const fullPath = `${this.workspace}/${file}`;
          const fileObj = Bun.file(fullPath);
          
          if (await fileObj.exists()) {
            const size = fileObj.size;
            if (size > maxFileSize) {
              largeFiles.push(`${file} (${(size / 1024 / 1024).toFixed(2)}MB)`);
            }
          }
        }
        
        if (largeFiles.length > 0) {
          return {
            continue: false,
            message: `Files too large: ${largeFiles.join(', ')}`
          };
        }
        
        return { continue: true };
      }
    });
  }
  
  private loadUserHooks() {
    // Load hooks from database
    const rows = this.db.query(
      "SELECT * FROM hooks WHERE enabled = 1"
    ).all() as any[];
    
    for (const row of rows) {
      // Skip default hooks (already registered)
      if (row.id.startsWith('validate-') || 
          row.id.startsWith('run-') || 
          row.id.startsWith('pre-') || 
          row.id.startsWith('post-') ||
          row.id.startsWith('file-')) {
        continue;
      }
      
      try {
        // Create hook from database
        const hook: Hook = {
          id: row.id,
          type: row.type,
          event: row.event,
          priority: row.priority,
          enabled: true,
          handler: this.createHandlerFromString(row.handler)
        };
        
        this.register(hook);
      } catch (error) {
        console.error(`Failed to load hook ${row.id}:`, error);
      }
    }
  }
  
  private createHandlerFromString(handlerStr: string): (context: HookContext) => Promise<HookResult> {
    // In production, this would need sandboxing
    // For now, just execute as shell command
    return async (context: HookContext) => {
      try {
        const result = await $`${handlerStr}`.quiet();
        
        return {
          continue: true,
          message: result.stdout
        };
      } catch (error) {
        return {
          continue: false,
          message: `Hook failed: ${error}`
        };
      }
    };
  }
  
  register(hook: Hook) {
    const eventHooks = this.hooks.get(hook.event) || [];
    eventHooks.push(hook);
    
    // Sort by priority (higher priority first)
    eventHooks.sort((a, b) => b.priority - a.priority);
    
    this.hooks.set(hook.event, eventHooks);
    
    console.log(`Registered hook: ${hook.id} for event ${hook.event}`);
  }
  
  unregister(hookId: string) {
    for (const [event, hooks] of this.hooks) {
      const index = hooks.findIndex(h => h.id === hookId);
      if (index >= 0) {
        hooks.splice(index, 1);
        console.log(`Unregistered hook: ${hookId}`);
        break;
      }
    }
  }
  
  enable(hookId: string) {
    this.setEnabled(hookId, true);
  }
  
  disable(hookId: string) {
    this.setEnabled(hookId, false);
  }
  
  private setEnabled(hookId: string, enabled: boolean) {
    for (const hooks of this.hooks.values()) {
      const hook = hooks.find(h => h.id === hookId);
      if (hook) {
        hook.enabled = enabled;
        
        // Update database
        this.db.run(
          "UPDATE hooks SET enabled = ?, updated_at = ? WHERE id = ?",
          [enabled ? 1 : 0, Date.now(), hookId]
        );
        
        console.log(`Hook ${hookId} ${enabled ? 'enabled' : 'disabled'}`);
        break;
      }
    }
  }
  
  async executeHooks(
    type: 'pre' | 'post',
    event: string,
    context: HookContext
  ): Promise<HookResult[]> {
    const eventHooks = this.hooks.get(event) || [];
    const relevantHooks = eventHooks
      .filter(h => h.type === type && h.enabled);
    
    const results: HookResult[] = [];
    
    for (const hook of relevantHooks) {
      const startTime = Date.now();
      
      try {
        console.log(`Executing ${type}-${event} hook: ${hook.id}`);
        
        const result = await hook.handler(context);
        results.push(result);
        
        // Log execution
        this.logExecution(hook.id, event, true, Date.now() - startTime);
        
        if (!result.continue) {
          console.log(`Hook ${hook.id} cancelled execution: ${result.message}`);
          break;
        }
        
        if (result.modifiedData) {
          // Update context for next hooks
          context.data = result.modifiedData;
        }
      } catch (error) {
        console.error(`Hook ${hook.id} failed:`, error);
        
        // Log failure
        this.logExecution(hook.id, event, false, Date.now() - startTime, error.message);
        
        // Continue with other hooks by default
        results.push({
          continue: true,
          message: `Hook ${hook.id} failed but continuing`
        });
      }
    }
    
    return results;
  }
  
  private logExecution(
    hookId: string,
    event: string,
    success: boolean,
    duration: number,
    error?: string
  ) {
    this.db.run(
      `INSERT INTO hook_executions (hook_id, event, success, duration, error, timestamp)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [hookId, event, success ? 1 : 0, duration, error || null, Date.now()]
    );
  }
  
  async createUserHook(
    id: string,
    type: 'pre' | 'post',
    event: string,
    handler: string,
    priority: number = 0
  ) {
    // Save to database
    this.db.run(
      `INSERT OR REPLACE INTO hooks 
       (id, type, event, name, handler, priority, enabled, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)`,
      [id, type, event, id, handler, priority, Date.now(), Date.now()]
    );
    
    // Create and register hook
    const hook: Hook = {
      id,
      type,
      event,
      priority,
      enabled: true,
      handler: this.createHandlerFromString(handler)
    };
    
    this.register(hook);
  }
  
  getHooks(event?: string): Hook[] {
    if (event) {
      return this.hooks.get(event) || [];
    }
    
    const allHooks: Hook[] = [];
    for (const hooks of this.hooks.values()) {
      allHooks.push(...hooks);
    }
    
    return allHooks;
  }
  
  getHookStats(): Map<string, {
    executions: number;
    successes: number;
    failures: number;
    avgDuration: number;
  }> {
    const stats = new Map();
    
    const rows = this.db.query(`
      SELECT 
        hook_id,
        COUNT(*) as executions,
        SUM(success) as successes,
        AVG(duration) as avg_duration
      FROM hook_executions
      GROUP BY hook_id
    `).all() as any[];
    
    for (const row of rows) {
      stats.set(row.hook_id, {
        executions: row.executions,
        successes: row.successes,
        failures: row.executions - row.successes,
        avgDuration: row.avg_duration
      });
    }
    
    return stats;
  }
}