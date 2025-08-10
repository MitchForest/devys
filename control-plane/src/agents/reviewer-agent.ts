import { BaseAgent } from './base-agent';
import { 
  AgentCapabilities, 
  AgentContext, 
  AgentResult,
  ReviewContext,
  ReviewResult,
  ReviewIssue,
  TestResult,
  Diff
} from '../types/agents';
import { Database } from 'bun:sqlite';
import { $ } from 'bun';

export class ReviewerAgent extends BaseAgent {
  constructor(workspace: string, db: Database) {
    super('reviewer', workspace, db);
  }
  
  defineCapabilities(): AgentCapabilities {
    return {
      maxTokens: 3000,
      preferredModel: 'gemini-pro',
      fallbackModels: ['claude-3-sonnet', 'gpt-4'],
      temperature: 0.2,
      systemPromptTemplate: 'reviewer-system-v1',
      tools: ['diff_analyzer', 'test_runner', 'lint_checker']
    };
  }
  
  validateInput(context: AgentContext): boolean {
    // Must have a ReviewContext as the task
    if (!context.task || typeof context.task !== 'object') {
      return false;
    }
    
    const reviewContext = context.task as ReviewContext;
    
    // Must have plan and edits
    if (!reviewContext.plan || !reviewContext.edits) {
      return false;
    }
    
    return true;
  }
  
  async formatContext(context: AgentContext): Promise<any> {
    const reviewContext = context.task as ReviewContext;
    
    // Get diffs and surrounding context
    const diffsWithContext = await this.getDiffsWithContext(reviewContext.edits);
    
    // Run automated checks
    const automatedChecks = await this.runAutomatedChecks(reviewContext.edits);
    
    return {
      plan: reviewContext.plan,
      changes: diffsWithContext,
      successCriteria: reviewContext.successCriteria,
      automatedChecks,
      originalRequest: reviewContext.originalContext?.task || 'Unknown task'
    };
  }
  
  processResult(rawResult: any): AgentResult {
    try {
      // Parse review from model output
      const review = this.parseReview(rawResult.content);
      
      // Calculate overall score
      review.score = this.calculateScore(review);
      
      // Determine if changes pass review
      review.passed = review.score >= 0.8 && 
                     review.issues.filter(i => i.severity === 'critical').length === 0;
      
      return {
        success: true,
        output: review,
        tokensUsed: rawResult.tokensUsed,
        modelUsed: rawResult.model,
        duration: 0, // Will be set by base class
        nextSteps: review.passed ? ['deploy'] : ['fix_issues']
      };
    } catch (error) {
      return {
        success: false,
        output: null,
        tokensUsed: rawResult.tokensUsed || 0,
        modelUsed: rawResult.model || 'unknown',
        duration: 0,
        errors: [error.message]
      };
    }
  }
  
  private async getDiffsWithContext(edits: any[]): Promise<DiffWithContext[]> {
    const diffs: DiffWithContext[] = [];
    
    for (const edit of edits) {
      if (!edit.diffs) continue;
      
      for (const diff of edit.diffs) {
        const context = await this.getFileContext(diff.file, diff.lineStart, diff.lineEnd);
        diffs.push({
          ...diff,
          context,
          relatedSymbols: await this.getRelatedSymbols(diff.file)
        });
      }
    }
    
    return diffs;
  }
  
  private async getFileContext(
    filePath: string,
    lineStart: number,
    lineEnd: number
  ): Promise<string> {
    const fullPath = `${this.workspace}/${filePath}`;
    const file = Bun.file(fullPath);
    
    if (!await file.exists()) {
      return '';
    }
    
    const content = await file.text();
    const lines = content.split('\n');
    
    // Get surrounding context (5 lines before and after)
    const contextStart = Math.max(0, lineStart - 5);
    const contextEnd = Math.min(lines.length, lineEnd + 5);
    
    return lines.slice(contextStart, contextEnd).join('\n');
  }
  
  private async getRelatedSymbols(filePath: string): Promise<any[]> {
    // Use context generator to get symbols from the file
    const context = await this.contextGenerator.generateContext({
      files: [filePath],
      includeCodeMap: true,
      includeContent: false
    });
    
    return context.codeMap?.symbols || [];
  }
  
  private async runAutomatedChecks(edits: any[]): Promise<AutomatedChecks> {
    const checks: AutomatedChecks = {
      linting: { passed: true, issues: [] },
      formatting: { passed: true, issues: [] },
      typecheck: { passed: true, issues: [] },
      tests: { passed: true, results: [] }
    };
    
    // Get all modified files
    const modifiedFiles = new Set<string>();
    for (const edit of edits) {
      if (edit.filesModified) {
        edit.filesModified.forEach((f: string) => modifiedFiles.add(f));
      }
      if (edit.filesCreated) {
        edit.filesCreated.forEach((f: string) => modifiedFiles.add(f));
      }
    }
    
    // Run checks on modified files
    for (const file of modifiedFiles) {
      await this.runFileChecks(file, checks);
    }
    
    // Run tests if available
    await this.runTests(checks);
    
    return checks;
  }
  
  private async runFileChecks(filePath: string, checks: AutomatedChecks): Promise<void> {
    const fullPath = `${this.workspace}/${filePath}`;
    
    // Determine file type
    const ext = filePath.split('.').pop()?.toLowerCase();
    
    if (ext === 'ts' || ext === 'tsx' || ext === 'js' || ext === 'jsx') {
      // Run TypeScript/JavaScript checks
      await this.runJSChecks(fullPath, checks);
    } else if (ext === 'py') {
      // Run Python checks
      await this.runPythonChecks(fullPath, checks);
    } else if (ext === 'rs') {
      // Run Rust checks
      await this.runRustChecks(fullPath, checks);
    }
  }
  
  private async runJSChecks(filePath: string, checks: AutomatedChecks): Promise<void> {
    try {
      // Try to run ESLint if available
      const lintResult = await $`npx eslint ${filePath} --format json`.quiet()
        .then(r => r.json())
        .catch(() => null);
      
      if (lintResult && lintResult[0]?.messages) {
        for (const msg of lintResult[0].messages) {
          checks.linting.issues.push({
            file: filePath,
            line: msg.line,
            message: msg.message,
            severity: msg.severity === 2 ? 'error' : 'warning'
          });
        }
        checks.linting.passed = lintResult[0].errorCount === 0;
      }
      
      // Try to run TypeScript compiler
      const tscResult = await $`npx tsc --noEmit ${filePath}`.quiet()
        .then(() => true)
        .catch(e => {
          const output = e.stderr || e.stdout || '';
          const lines = output.split('\n');
          for (const line of lines) {
            if (line.includes('error TS')) {
              checks.typecheck.issues.push({
                file: filePath,
                message: line,
                severity: 'error'
              });
            }
          }
          return false;
        });
      
      checks.typecheck.passed = tscResult;
      
    } catch (error) {
      // Tools not available, skip
    }
  }
  
  private async runPythonChecks(filePath: string, checks: AutomatedChecks): Promise<void> {
    try {
      // Try to run pylint if available
      const pylintResult = await $`pylint ${filePath} --output-format=json`.quiet()
        .then(r => r.json())
        .catch(() => null);
      
      if (pylintResult && Array.isArray(pylintResult)) {
        for (const msg of pylintResult) {
          checks.linting.issues.push({
            file: filePath,
            line: msg.line,
            message: msg.message,
            severity: msg.type === 'error' ? 'error' : 'warning'
          });
        }
        checks.linting.passed = pylintResult.filter(m => m.type === 'error').length === 0;
      }
      
    } catch (error) {
      // Tools not available, skip
    }
  }
  
  private async runRustChecks(filePath: string, checks: AutomatedChecks): Promise<void> {
    try {
      // Try to run cargo check if in a Rust project
      const checkResult = await $`cargo check --message-format=json`.quiet()
        .then(() => true)
        .catch(e => {
          const output = e.stdout || '';
          const lines = output.split('\n');
          for (const line of lines) {
            try {
              const msg = JSON.parse(line);
              if (msg.reason === 'compiler-message' && msg.message) {
                checks.typecheck.issues.push({
                  file: filePath,
                  message: msg.message.rendered,
                  severity: msg.message.level === 'error' ? 'error' : 'warning'
                });
              }
            } catch {}
          }
          return false;
        });
      
      checks.typecheck.passed = checkResult;
      
    } catch (error) {
      // Tools not available, skip
    }
  }
  
  private async runTests(checks: AutomatedChecks): Promise<void> {
    try {
      // Try to run tests based on what's available
      let testCommand = '';
      
      // Check for test runner
      const packageJson = Bun.file(`${this.workspace}/package.json`);
      if (await packageJson.exists()) {
        const pkg = await packageJson.json();
        if (pkg.scripts?.test) {
          testCommand = 'npm test';
        } else if (pkg.devDependencies?.['bun-test']) {
          testCommand = 'bun test';
        }
      }
      
      if (!testCommand) {
        // Check for other test files
        const cargoToml = Bun.file(`${this.workspace}/Cargo.toml`);
        if (await cargoToml.exists()) {
          testCommand = 'cargo test';
        }
      }
      
      if (testCommand) {
        const result = await $`${testCommand}`.quiet()
          .then(() => ({ passed: true, output: '' }))
          .catch(e => ({ passed: false, output: e.stderr || e.stdout || '' }));
        
        checks.tests.passed = result.passed;
        checks.tests.results.push({
          name: 'All tests',
          passed: result.passed,
          error: result.passed ? undefined : result.output,
          duration: 0
        });
      }
      
    } catch (error) {
      // Tests not available, skip
    }
  }
  
  private parseReview(content: string): ReviewResult {
    const issues: ReviewIssue[] = [];
    const suggestions: string[] = [];
    
    // Parse issues section
    const issuesMatch = content.match(/### ISSUES\n([\s\S]*?)(?=###|$)/i);
    if (issuesMatch) {
      const issueLines = issuesMatch[1].split('\n').filter(line => line.trim());
      for (const line of issueLines) {
        // Parse format: [SEVERITY] file:line - message
        const match = line.match(/\[(CRITICAL|WARNING|INFO)\]\s*([^:]+):?(\d+)?\s*-\s*(.+)/i);
        if (match) {
          issues.push({
            severity: match[1].toLowerCase() as 'critical' | 'warning' | 'info',
            file: match[2].trim(),
            line: match[3] ? parseInt(match[3], 10) : undefined,
            message: match[4].trim()
          });
        }
      }
    }
    
    // Parse suggestions section
    const suggestionsMatch = content.match(/### SUGGESTIONS\n([\s\S]*?)(?=###|$)/i);
    if (suggestionsMatch) {
      const suggestionLines = suggestionsMatch[1].split('\n').filter(line => line.trim());
      for (const line of suggestionLines) {
        const cleaned = line.replace(/^[-*\s]+/, '').trim();
        if (cleaned) suggestions.push(cleaned);
      }
    }
    
    // Parse overall assessment
    const passedMatch = content.match(/### ASSESSMENT:\s*(PASS|FAIL)/i);
    const passed = passedMatch ? passedMatch[1].toUpperCase() === 'PASS' : false;
    
    return {
      passed,
      score: 0, // Will be calculated
      issues,
      suggestions,
      testResults: []
    };
  }
  
  private calculateScore(review: ReviewResult): number {
    let score = 1.0;
    
    // Deduct for issues
    for (const issue of review.issues) {
      switch (issue.severity) {
        case 'critical': score -= 0.3; break;
        case 'warning': score -= 0.1; break;
        case 'info': score -= 0.02; break;
      }
    }
    
    // Deduct for failed tests
    if (review.testResults && review.testResults.length > 0) {
      const passRate = review.testResults.filter(t => t.passed).length / review.testResults.length;
      score *= passRate;
    }
    
    return Math.max(0, Math.min(1, score));
  }
}

interface DiffWithContext extends Diff {
  context: string;
  relatedSymbols: any[];
}

interface AutomatedChecks {
  linting: {
    passed: boolean;
    issues: Array<{
      file: string;
      line?: number;
      message: string;
      severity: 'error' | 'warning';
    }>;
  };
  formatting: {
    passed: boolean;
    issues: any[];
  };
  typecheck: {
    passed: boolean;
    issues: any[];
  };
  tests: {
    passed: boolean;
    results: TestResult[];
  };
}