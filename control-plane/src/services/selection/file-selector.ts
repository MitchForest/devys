import { minimatch } from 'minimatch';
import ignore from 'ignore';
import { $ } from 'bun';
import type { SelectionOptions } from '../../types/context';

export class FileSelector {
  private gitignore: ReturnType<typeof ignore> | null = null;
  private aiignore: ReturnType<typeof ignore> | null = null;
  
  constructor(private workspace: string) {}
  
  async selectFiles(options: SelectionOptions): Promise<string[]> {
    let files: Set<string> = new Set();
    
    // Load ignore patterns
    if (options.useGitignore) {
      this.gitignore = await this.loadGitignore();
    }
    if (options.useAiIgnore) {
      this.aiignore = await this.loadAiIgnore();
    }
    
    // Manual file selection
    if (options.files && options.files.length > 0) {
      for (const file of options.files) {
        const fullPath = this.resolveFilePath(file);
        if (await this.fileExists(fullPath)) {
          files.add(fullPath);
        }
      }
    }
    
    // Folder selection
    if (options.folders && options.folders.length > 0) {
      for (const folder of options.folders) {
        const folderFiles = await this.getFilesInFolder(folder);
        folderFiles.forEach(f => files.add(f));
      }
    }
    
    // Pattern matching
    if (options.patterns && options.patterns.length > 0) {
      for (const pattern of options.patterns) {
        const matched = await this.glob(pattern);
        matched.forEach(f => files.add(f));
      }
    }
    
    // If no specific selection, get all files
    if (files.size === 0 && !options.files && !options.folders && !options.patterns) {
      const allFiles = await this.getAllFiles();
      allFiles.forEach(f => files.add(f));
    }
    
    // Apply exclusions
    if (options.excludePatterns && options.excludePatterns.length > 0) {
      files = this.applyExclusions(files, options.excludePatterns);
    }
    
    // Apply .gitignore
    if (this.gitignore) {
      files = this.applyIgnoreFile(files, this.gitignore);
    }
    
    // Apply .aiignore
    if (this.aiignore) {
      files = this.applyIgnoreFile(files, this.aiignore);
    }
    
    // Convert to array and apply limits
    let fileArray = Array.from(files);
    
    // Sort by importance (can be enhanced with working set data)
    fileArray = await this.sortByImportance(fileArray);
    
    // Limit file count
    if (options.maxFiles && fileArray.length > options.maxFiles) {
      fileArray = fileArray.slice(0, options.maxFiles);
    }
    
    return fileArray;
  }
  
  private async loadGitignore(): Promise<ReturnType<typeof ignore>> {
    const ig = ignore();
    
    try {
      const gitignorePath = `${this.workspace}/.gitignore`;
      const file = Bun.file(gitignorePath);
      if (await file.exists()) {
        const content = await file.text();
        ig.add(content);
      }
    } catch {
      // No .gitignore or error reading it
    }
    
    // Add default patterns
    ig.add([
      'node_modules',
      '.git',
      'dist',
      'build',
      '*.log',
      '.DS_Store',
      'coverage',
      '.env*'
    ]);
    
    return ig;
  }
  
  private async loadAiIgnore(): Promise<ReturnType<typeof ignore>> {
    const ig = ignore();
    
    try {
      const aiignorePath = `${this.workspace}/.aiignore`;
      const file = Bun.file(aiignorePath);
      if (await file.exists()) {
        const content = await file.text();
        ig.add(content);
      }
    } catch {
      // No .aiignore or error reading it
    }
    
    return ig;
  }
  
  private async getFilesInFolder(folder: string): Promise<string[]> {
    const fullPath = this.resolveFilePath(folder);
    const files: string[] = [];
    
    try {
      const result = await $`find ${fullPath} -type f -not -path "*/.*" 2>/dev/null`.quiet();
      const lines = result.text().trim().split('\n').filter(Boolean);
      files.push(...lines);
    } catch {
      // Folder doesn't exist or error
    }
    
    return files;
  }
  
  private async glob(pattern: string): Promise<string[]> {
    const files: string[] = [];
    
    try {
      // Use find command with pattern matching
      const result = await $`cd ${this.workspace} && find . -type f -name "${pattern}" 2>/dev/null`.quiet();
      const lines = result.text().trim().split('\n').filter(Boolean);
      
      // Convert relative paths to absolute
      for (const line of lines) {
        const cleanPath = line.startsWith('./') ? line.slice(2) : line;
        files.push(`${this.workspace}/${cleanPath}`);
      }
    } catch {
      // Pattern didn't match anything
    }
    
    // Also use minimatch for more complex patterns
    if (pattern.includes('**') || pattern.includes('{') || pattern.includes('[')) {
      const allFiles = await this.getAllFiles();
      for (const file of allFiles) {
        const relativePath = this.getRelativePath(file);
        if (minimatch(relativePath, pattern, { dot: true })) {
          files.push(file);
        }
      }
    }
    
    return [...new Set(files)]; // Remove duplicates
  }
  
  private async getAllFiles(): Promise<string[]> {
    const files: string[] = [];
    
    try {
      const result = await $`find ${this.workspace} -type f -not -path "*/.*" 2>/dev/null`.quiet();
      const lines = result.text().trim().split('\n').filter(Boolean);
      files.push(...lines);
    } catch {
      // Error getting files
    }
    
    return files;
  }
  
  private applyExclusions(files: Set<string>, patterns: string[]): Set<string> {
    const filtered = new Set<string>();
    
    for (const file of files) {
      const relativePath = this.getRelativePath(file);
      let excluded = false;
      
      for (const pattern of patterns) {
        if (minimatch(relativePath, pattern, { dot: true })) {
          excluded = true;
          break;
        }
      }
      
      if (!excluded) {
        filtered.add(file);
      }
    }
    
    return filtered;
  }
  
  private applyIgnoreFile(files: Set<string>, ig: ReturnType<typeof ignore>): Set<string> {
    const filtered = new Set<string>();
    
    for (const file of files) {
      const relativePath = this.getRelativePath(file);
      if (!ig.ignores(relativePath)) {
        filtered.add(file);
      }
    }
    
    return filtered;
  }
  
  private async sortByImportance(files: string[]): Promise<string[]> {
    // Simple heuristic sorting
    return files.sort((a, b) => {
      // Prioritize certain file types
      const scoreA = this.getFileImportanceScore(a);
      const scoreB = this.getFileImportanceScore(b);
      return scoreB - scoreA;
    });
  }
  
  private getFileImportanceScore(file: string): number {
    let score = 0;
    const name = file.split('/').pop() || '';
    
    // Entry points are most important
    if (name === 'index.ts' || name === 'index.js' || name === 'main.ts' || name === 'main.js') {
      score += 100;
    }
    
    // App/server files
    if (name.includes('app.') || name.includes('server.')) {
      score += 50;
    }
    
    // Configuration files
    if (name === 'package.json' || name === 'tsconfig.json' || name.endsWith('.config.js')) {
      score += 30;
    }
    
    // Source files over test files
    if (file.includes('/src/')) {
      score += 20;
    } else if (file.includes('/test/') || file.includes('.test.') || file.includes('.spec.')) {
      score -= 10;
    }
    
    // Documentation is lower priority
    if (file.endsWith('.md')) {
      score -= 20;
    }
    
    return score;
  }
  
  private resolveFilePath(path: string): string {
    if (path.startsWith('/')) {
      return path;
    }
    return `${this.workspace}/${path}`;
  }
  
  private getRelativePath(file: string): string {
    if (file.startsWith(this.workspace)) {
      return file.slice(this.workspace.length + 1);
    }
    return file;
  }
  
  private async fileExists(path: string): Promise<boolean> {
    try {
      const file = Bun.file(path);
      return await file.exists();
    } catch {
      return false;
    }
  }
}