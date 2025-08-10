import type { WorkingSet } from '../../types/context';
import { GitManager } from './git-manager';

export class WorkingSetTracker {
  private gitManager: GitManager;
  private openFiles: Set<string> = new Set();
  private fileAccessTimes: Map<string, number> = new Map();
  
  constructor(private workspace: string) {
    this.gitManager = new GitManager(workspace);
  }
  
  async getWorkingSet(): Promise<WorkingSet> {
    const gitWorkingSet = await this.gitManager.getWorkingSet();
    
    // Merge with tracked open files
    gitWorkingSet.openFiles = Array.from(this.openFiles);
    
    return gitWorkingSet;
  }
  
  trackFileOpen(filePath: string) {
    const relativePath = this.makeRelative(filePath);
    this.openFiles.add(relativePath);
    this.fileAccessTimes.set(relativePath, Date.now());
  }
  
  trackFileClose(filePath: string) {
    const relativePath = this.makeRelative(filePath);
    this.openFiles.delete(relativePath);
  }
  
  isInWorkingSet(filePath: string, workingSet: WorkingSet): boolean {
    const relativePath = this.makeRelative(filePath);
    
    return workingSet.openFiles.includes(relativePath) ||
           workingSet.recentlyModified.includes(relativePath) ||
           workingSet.gitChanges.includes(relativePath);
  }
  
  async getFileImportance(filePath: string): Promise<number> {
    const relativePath = this.makeRelative(filePath);
    let score = 0;
    
    // Is file open?
    if (this.openFiles.has(relativePath)) {
      score += 50;
    }
    
    // Recently accessed?
    const lastAccess = this.fileAccessTimes.get(relativePath);
    if (lastAccess) {
      const hoursSinceAccess = (Date.now() - lastAccess) / 3600000;
      if (hoursSinceAccess < 1) score += 30;
      else if (hoursSinceAccess < 24) score += 15;
    }
    
    // Has git changes?
    const gitChanges = await this.gitManager.getChangedFiles();
    if (gitChanges.includes(relativePath)) {
      score += 40;
    }
    
    // Recently modified in git?
    const recentFiles = await this.gitManager.getRecentlyModifiedFiles(24);
    if (recentFiles.includes(relativePath)) {
      score += 20;
    }
    
    // Entry point file?
    if (relativePath.includes('index') || relativePath.includes('main')) {
      score += 25;
    }
    
    return score;
  }
  
  async getRecentlyModifiedFiles(hours: number = 24): Promise<string[]> {
    const cutoff = Date.now() - (hours * 3600000);
    const files: string[] = [];
    
    // Check file system modification times
    for (const [file, _] of this.fileAccessTimes) {
      try {
        const fullPath = `${this.workspace}/${file}`;
        const bunFile = Bun.file(fullPath);
        const stats = await bunFile.stat();
        if (stats.mtime.getTime() > cutoff) {
          files.push(file);
        }
      } catch {
        // File might not exist anymore
      }
    }
    
    // Also get from git
    const gitRecent = await this.gitManager.getRecentlyModifiedFiles(hours);
    
    return [...new Set([...files, ...gitRecent])];
  }
  
  clearOpenFiles() {
    this.openFiles.clear();
  }
  
  getOpenFilesList(): string[] {
    return Array.from(this.openFiles);
  }
  
  private makeRelative(filePath: string): string {
    if (filePath.startsWith(this.workspace)) {
      return filePath.slice(this.workspace.length + 1);
    }
    return filePath;
  }
}