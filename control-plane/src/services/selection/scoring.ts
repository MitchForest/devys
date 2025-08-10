import type { ExtractedSymbol, SelectionRules, WorkingSet } from '../../types/context';
import { GitManager } from '../git/git-manager';
import { WorkingSetTracker } from '../git/working-set';

export class ContextScorer {
  private gitManager: GitManager;
  private workingSetTracker: WorkingSetTracker;
  
  constructor(private workspace: string) {
    this.gitManager = new GitManager(workspace);
    this.workingSetTracker = new WorkingSetTracker(workspace);
  }
  
  async scoreSymbol(
    symbol: ExtractedSymbol,
    rules: SelectionRules,
    workingSet?: WorkingSet
  ): Promise<number> {
    let score = 0;
    
    // Public API surface is most important
    if (symbol.exported) {
      score += rules.priorityWeights.exported;
    }
    
    // Check if file is in working set
    if (workingSet && symbol.file) {
      const isInWorkingSet = this.workingSetTracker.isInWorkingSet(
        symbol.file,
        workingSet
      );
      if (isInWorkingSet) {
        score += rules.workingSetBoost;
      }
    }
    
    // Recently modified symbols likely relevant
    if (symbol.file) {
      const recencyScore = await this.calculateRecencyScore(
        symbol.file,
        rules.priorityWeights.recent,
        rules.recencyDecay
      );
      score += recencyScore;
    }
    
    // Complex code needs more attention
    if (symbol.complexity && symbol.complexity > 5) {
      const complexityBonus = Math.min(
        symbol.complexity * 2,
        rules.priorityWeights.complex
      );
      score += complexityBonus;
    }
    
    // Frequently referenced = important
    if (symbol.references) {
      const refBonus = Math.min(
        symbol.references * 2,
        rules.priorityWeights.referenced
      );
      score += refBonus;
    }
    
    // Entry points are critical
    if (symbol.file && this.isEntryPoint(symbol.file)) {
      score += rules.priorityWeights.entryPoint;
    }
    
    // Has documentation = important API
    if (symbol.signature && symbol.signature.includes('/**')) {
      score += rules.priorityWeights.documented;
    }
    
    return score;
  }
  
  async scoreFile(
    filePath: string,
    rules: SelectionRules,
    workingSet?: WorkingSet
  ): Promise<number> {
    let score = 0;
    
    // Check if file is in working set
    if (workingSet) {
      const isInWorkingSet = this.workingSetTracker.isInWorkingSet(
        filePath,
        workingSet
      );
      if (isInWorkingSet) {
        score += rules.workingSetBoost * 2; // Double boost for files
      }
    }
    
    // Recently modified files
    const recencyScore = await this.calculateRecencyScore(
      filePath,
      rules.priorityWeights.recent * 2,
      rules.recencyDecay
    );
    score += recencyScore;
    
    // Entry points
    if (this.isEntryPoint(filePath)) {
      score += rules.priorityWeights.entryPoint * 2;
    }
    
    // Test files (if they exist for this file)
    if (await this.hasTestFile(filePath)) {
      score += rules.priorityWeights.hasTests;
    }
    
    // File type importance
    score += this.getFileTypeScore(filePath);
    
    // Pattern matching
    for (const pattern of rules.includePatterns) {
      if (this.matchesPattern(filePath, pattern)) {
        score += 20;
      }
    }
    
    for (const pattern of rules.excludePatterns) {
      if (this.matchesPattern(filePath, pattern)) {
        score -= 50;
      }
    }
    
    return Math.max(score, 0);
  }
  
  private async calculateRecencyScore(
    filePath: string,
    maxScore: number,
    decayFactor: number
  ): Promise<number> {
    try {
      const file = Bun.file(filePath);
      const stats = await file.stat();
      const hoursSinceModified = (Date.now() - stats.mtime.getTime()) / 3600000;
      
      // Exponential decay based on time
      const decayMultiplier = Math.exp(-decayFactor * hoursSinceModified);
      return Math.floor(maxScore * decayMultiplier);
    } catch {
      return 0;
    }
  }
  
  private isEntryPoint(filePath: string): boolean {
    const name = filePath.split('/').pop() || '';
    const entryPointNames = [
      'index.ts', 'index.js', 'index.tsx', 'index.jsx',
      'main.ts', 'main.js',
      'app.ts', 'app.js', 'app.tsx', 'app.jsx',
      'server.ts', 'server.js',
      'cli.ts', 'cli.js'
    ];
    
    return entryPointNames.includes(name);
  }
  
  private async hasTestFile(filePath: string): Promise<boolean> {
    // Check for corresponding test file
    const testPatterns = [
      filePath.replace(/\.(ts|js|tsx|jsx)$/, '.test.$1'),
      filePath.replace(/\.(ts|js|tsx|jsx)$/, '.spec.$1'),
      filePath.replace(/\/src\//, '/test/').replace(/\.(ts|js|tsx|jsx)$/, '.test.$1'),
      filePath.replace(/\/src\//, '/__tests__/').replace(/\.(ts|js|tsx|jsx)$/, '.test.$1')
    ];
    
    for (const testPath of testPatterns) {
      const file = Bun.file(testPath);
      if (await file.exists()) {
        return true;
      }
    }
    
    return false;
  }
  
  private getFileTypeScore(filePath: string): number {
    const ext = this.getFileExtension(filePath);
    const name = filePath.split('/').pop() || '';
    
    // Configuration files are important
    if (name === 'package.json') return 30;
    if (name === 'tsconfig.json') return 25;
    if (name.endsWith('.config.js') || name.endsWith('.config.ts')) return 20;
    
    // Source code files
    if (['.ts', '.tsx', '.js', '.jsx'].includes(ext)) return 15;
    if (['.py', '.rs', '.go', '.java'].includes(ext)) return 15;
    
    // Style files
    if (['.css', '.scss', '.less'].includes(ext)) return 5;
    
    // Documentation
    if (ext === '.md') return -5;
    
    // Test files
    if (filePath.includes('.test.') || filePath.includes('.spec.')) return -10;
    
    return 0;
  }
  
  private matchesPattern(filePath: string, pattern: string): boolean {
    // Simple pattern matching
    if (pattern.includes('*')) {
      const regex = new RegExp(
        '^' + pattern.replace(/\*/g, '.*').replace(/\?/g, '.') + '$'
      );
      return regex.test(filePath);
    }
    
    return filePath.includes(pattern);
  }
  
  private getFileExtension(filePath: string): string {
    const lastDot = filePath.lastIndexOf('.');
    return lastDot > -1 ? filePath.slice(lastDot) : '';
  }
  
  getDefaultRules(): SelectionRules {
    return {
      maxTokens: 100000,
      maxFiles: 100,
      priorityWeights: {
        exported: 20,
        recent: 15,
        complex: 10,
        referenced: 10,
        hasTests: 5,
        documented: 5,
        entryPoint: 25
      },
      includePatterns: ['src/**/*', 'lib/**/*'],
      excludePatterns: ['node_modules/**', 'dist/**', 'build/**', '*.test.*', '*.spec.*'],
      workingSetBoost: 30,
      recencyDecay: 0.1
    };
  }
}