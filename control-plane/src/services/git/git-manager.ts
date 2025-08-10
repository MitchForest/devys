import { $ } from 'bun';
import type { WorkingSet } from '../../types/context';

export class GitManager {
  constructor(private workspace: string) {}
  
  async getCurrentCommit(): Promise<string | undefined> {
    try {
      const result = await $`cd ${this.workspace} && git rev-parse HEAD`.quiet();
      return result.text().trim();
    } catch {
      return undefined;
    }
  }
  
  async getCurrentBranch(): Promise<string> {
    try {
      const result = await $`cd ${this.workspace} && git branch --show-current`.quiet();
      return result.text().trim() || 'main';
    } catch {
      return 'main';
    }
  }
  
  async getChangedFiles(): Promise<string[]> {
    try {
      // Get both staged and unstaged changes
      const result = await $`cd ${this.workspace} && git diff --name-only HEAD`.quiet();
      const files = result.text().trim().split('\n').filter(Boolean);
      
      // Also get untracked files
      const untracked = await $`cd ${this.workspace} && git ls-files --others --exclude-standard`.quiet();
      const untrackedFiles = untracked.text().trim().split('\n').filter(Boolean);
      
      return [...new Set([...files, ...untrackedFiles])];
    } catch {
      return [];
    }
  }
  
  async getRecentCommits(limit: number = 10): Promise<Array<{
    sha: string;
    message: string;
    author: string;
    timestamp: number;
    files: string[];
  }>> {
    try {
      const result = await $`cd ${this.workspace} && git log --pretty=format:"%H|%s|%an|%at" -n ${limit}`.quiet();
      const lines = result.text().trim().split('\n').filter(Boolean);
      
      const commits = await Promise.all(lines.map(async line => {
        const [sha, message, author, timestamp] = line.split('|');
        
        // Get files changed in this commit
        const filesResult = await $`cd ${this.workspace} && git diff-tree --no-commit-id --name-only -r ${sha}`.quiet();
        const files = filesResult.text().trim().split('\n').filter(Boolean);
        
        return {
          sha,
          message,
          author,
          timestamp: parseInt(timestamp) * 1000,
          files
        };
      }));
      
      return commits;
    } catch {
      return [];
    }
  }
  
  async getFileHistory(filePath: string, limit: number = 10): Promise<Array<{
    sha: string;
    message: string;
    timestamp: number;
  }>> {
    try {
      const result = await $`cd ${this.workspace} && git log --pretty=format:"%H|%s|%at" -n ${limit} -- ${filePath}`.quiet();
      const lines = result.text().trim().split('\n').filter(Boolean);
      
      return lines.map(line => {
        const [sha, message, timestamp] = line.split('|');
        return {
          sha,
          message,
          timestamp: parseInt(timestamp) * 1000
        };
      });
    } catch {
      return [];
    }
  }
  
  async getRecentlyModifiedFiles(hours: number = 24): Promise<string[]> {
    try {
      // Use git log to find files modified in the last N hours
      const result = await $`cd ${this.workspace} && git log --since="${hours} hours ago" --name-only --pretty=format:""`.quiet();
      const files = result.text().trim().split('\n').filter(Boolean);
      return [...new Set(files)]; // Remove duplicates
    } catch {
      return [];
    }
  }
  
  async isGitRepository(): Promise<boolean> {
    try {
      await $`cd ${this.workspace} && git rev-parse --git-dir`.quiet();
      return true;
    } catch {
      return false;
    }
  }
  
  async getWorkingSet(): Promise<WorkingSet> {
    const [currentBranch, gitChanges, recentlyModified] = await Promise.all([
      this.getCurrentBranch(),
      this.getChangedFiles(),
      this.getRecentlyModifiedFiles(1) // Last hour
    ]);
    
    return {
      openFiles: [], // Will be populated from editor integration
      recentlyModified,
      gitChanges,
      currentBranch
    };
  }
  
  async getCommitsBetween(oldCommit: string, newCommit: string = 'HEAD'): Promise<string[]> {
    try {
      const result = await $`cd ${this.workspace} && git rev-list ${oldCommit}..${newCommit}`.quiet();
      return result.text().trim().split('\n').filter(Boolean);
    } catch {
      return [];
    }
  }
  
  async getFilesChangedBetween(oldCommit: string, newCommit: string = 'HEAD'): Promise<string[]> {
    try {
      const result = await $`cd ${this.workspace} && git diff --name-only ${oldCommit}..${newCommit}`.quiet();
      return result.text().trim().split('\n').filter(Boolean);
    } catch {
      return [];
    }
  }
}