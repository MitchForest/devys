import { watch, type FSWatcher, type WatchEventType } from 'fs';
import { EventEmitter } from 'events';
import type { ContextGenerator } from '../context/context-generator';

export interface FileChangeEvent {
  type: 'add' | 'change' | 'rename' | 'delete';
  path: string;
  timestamp: number;
}

export class IncrementalUpdater extends EventEmitter {
  private watcher: FSWatcher | null = null;
  private updateQueue: Set<string> = new Set();
  private debounceTimer: Timer | null = null;
  private debounceMs: number = 100;
  private isWatching: boolean = false;
  
  constructor(
    private workspace: string,
    private contextGenerator: ContextGenerator
  ) {
    super();
  }
  
  start() {
    if (this.isWatching) return;
    
    try {
      this.watcher = watch(this.workspace, {
        recursive: true,
        persistent: true
      }, (eventType, filename) => {
        if (filename) {
          this.handleFileChange(eventType, filename);
        }
      });
      
      this.isWatching = true;
      console.log(`📡 File watcher started for ${this.workspace}`);
      
      // Handle watcher errors
      this.watcher.on('error', (error) => {
        console.error('File watcher error:', error);
        this.emit('error', error);
      });
      
    } catch (error) {
      console.error('Failed to start file watcher:', error);
      throw error;
    }
  }
  
  stop() {
    if (this.watcher) {
      this.watcher.close();
      this.watcher = null;
      this.isWatching = false;
      console.log('File watcher stopped');
    }
    
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    
    this.updateQueue.clear();
  }
  
  private handleFileChange(eventType: WatchEventType, filename: string) {
    // Filter out unwanted files
    if (this.shouldIgnore(filename)) {
      return;
    }
    
    const fullPath = `${this.workspace}/${filename}`;
    
    // Map event type
    let changeType: FileChangeEvent['type'] = 'change';
    if (eventType === 'rename') {
      changeType = 'rename';
    }
    
    // Add to update queue
    this.updateQueue.add(fullPath);
    
    // Emit immediate event for UI updates
    const event: FileChangeEvent = {
      type: changeType,
      path: fullPath,
      timestamp: Date.now()
    };
    this.emit('file-change', event);
    
    // Debounce context regeneration
    this.scheduleUpdate();
  }
  
  private scheduleUpdate() {
    // Clear existing timer
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }
    
    // Schedule new update
    this.debounceTimer = setTimeout(() => {
      this.processUpdates();
    }, this.debounceMs) as any;
  }
  
  private async processUpdates() {
    if (this.updateQueue.size === 0) return;
    
    const files = Array.from(this.updateQueue);
    this.updateQueue.clear();
    
    const startTime = performance.now();
    console.log(`🔄 Processing incremental updates for ${files.length} files...`);
    
    try {
      // Invalidate cache for changed files
      for (const file of files) {
        await this.contextGenerator.cacheManager.invalidateFile(file);
      }
      
      // Trigger context update
      const context = await this.contextGenerator.updateContext('file_save', {
        files,
        incremental: true
      });
      
      const elapsed = performance.now() - startTime;
      console.log(`✅ Incremental update completed in ${elapsed.toFixed(2)}ms`);
      
      // Emit context update event
      this.emit('context-updated', {
        files,
        context,
        timestamp: Date.now(),
        duration: elapsed
      });
      
    } catch (error) {
      console.error('Incremental update failed:', error);
      this.emit('error', error);
    }
  }
  
  private shouldIgnore(filename: string): boolean {
    // Ignore patterns
    const ignorePatterns = [
      '.git',
      'node_modules',
      '.DS_Store',
      '*.log',
      'dist',
      'build',
      'coverage',
      '.env',
      '*.swp',
      '*.tmp',
      '~*'
    ];
    
    for (const pattern of ignorePatterns) {
      if (pattern.includes('*')) {
        // Simple wildcard matching
        const regex = new RegExp('^' + pattern.replace(/\*/g, '.*') + '$');
        if (regex.test(filename)) {
          return true;
        }
      } else if (filename.includes(pattern)) {
        return true;
      }
    }
    
    return false;
  }
  
  setDebounceMs(ms: number) {
    this.debounceMs = ms;
  }
  
  getQueueSize(): number {
    return this.updateQueue.size;
  }
  
  isRunning(): boolean {
    return this.isWatching;
  }
}