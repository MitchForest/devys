export class TokenCounter {
  // Approximation: 1 token ≈ 4 characters for English text
  // This is a rough estimate; actual tokenization varies by model
  private readonly CHARS_PER_TOKEN = 4;
  
  // More accurate estimates for different file types
  private readonly languageMultipliers: Record<string, number> = {
    'typescript': 3.5,  // More dense due to keywords
    'javascript': 3.5,
    'python': 3.8,
    'rust': 3.2,        // Very dense syntax
    'go': 3.6,
    'java': 3.4,
    'html': 4.5,        // Less dense
    'css': 4.2,
    'json': 3.8,
    'yaml': 4.2,
    'markdown': 4.5,
    'text': 4.0
  };
  
  estimateTokens(text: string, language?: string): number {
    if (!text) return 0;
    
    const multiplier = language && this.languageMultipliers[language]
      ? this.languageMultipliers[language]
      : this.CHARS_PER_TOKEN;
    
    // Basic calculation
    let tokens = Math.ceil(text.length / multiplier);
    
    // Adjust for whitespace density
    const lines = text.split('\n');
    const emptyLines = lines.filter(l => l.trim() === '').length;
    const whitespaceRatio = emptyLines / Math.max(lines.length, 1);
    
    // Reduce token count for files with lots of whitespace
    if (whitespaceRatio > 0.2) {
      tokens = Math.ceil(tokens * (1 - whitespaceRatio * 0.3));
    }
    
    return tokens;
  }
  
  async countFile(filePath: string): Promise<number> {
    try {
      const file = Bun.file(filePath);
      const content = await file.text();
      const language = this.detectLanguage(filePath);
      return this.estimateTokens(content, language);
    } catch {
      return 0;
    }
  }
  
  async countFiles(filePaths: string[]): Promise<Map<string, number>> {
    const counts = new Map<string, number>();
    
    await Promise.all(
      filePaths.map(async path => {
        const count = await this.countFile(path);
        counts.set(path, count);
      })
    );
    
    return counts;
  }
  
  optimizeForLimit(
    files: Map<string, number>,
    limit: number,
    priorityScores?: Map<string, number>
  ): string[] {
    // Create array with file info
    const fileArray = Array.from(files.entries()).map(([file, tokens]) => ({
      file,
      tokens,
      priority: priorityScores?.get(file) || 0
    }));
    
    // Sort by priority (higher first), then by tokens (smaller first)
    fileArray.sort((a, b) => {
      if (Math.abs(a.priority - b.priority) > 0.01) {
        return b.priority - a.priority;
      }
      return a.tokens - b.tokens;
    });
    
    const selected: string[] = [];
    let totalTokens = 0;
    
    for (const { file, tokens } of fileArray) {
      if (totalTokens + tokens <= limit) {
        selected.push(file);
        totalTokens += tokens;
      } else if (selected.length === 0 && tokens <= limit) {
        // Include at least one file if possible
        selected.push(file);
        break;
      }
    }
    
    return selected;
  }
  
  splitIntoChunks(
    text: string,
    maxTokensPerChunk: number,
    language?: string
  ): string[] {
    const estimatedTokens = this.estimateTokens(text, language);
    
    if (estimatedTokens <= maxTokensPerChunk) {
      return [text];
    }
    
    const chunks: string[] = [];
    const lines = text.split('\n');
    let currentChunk: string[] = [];
    let currentTokens = 0;
    
    for (const line of lines) {
      const lineTokens = this.estimateTokens(line + '\n', language);
      
      if (currentTokens + lineTokens > maxTokensPerChunk && currentChunk.length > 0) {
        // Start new chunk
        chunks.push(currentChunk.join('\n'));
        currentChunk = [line];
        currentTokens = lineTokens;
      } else {
        currentChunk.push(line);
        currentTokens += lineTokens;
      }
    }
    
    if (currentChunk.length > 0) {
      chunks.push(currentChunk.join('\n'));
    }
    
    return chunks;
  }
  
  private detectLanguage(filePath: string): string | undefined {
    const ext = this.getFileExtension(filePath);
    const extMap: Record<string, string> = {
      '.ts': 'typescript',
      '.tsx': 'typescript',
      '.js': 'javascript',
      '.jsx': 'javascript',
      '.py': 'python',
      '.rs': 'rust',
      '.go': 'go',
      '.java': 'java',
      '.html': 'html',
      '.css': 'css',
      '.json': 'json',
      '.yaml': 'yaml',
      '.yml': 'yaml',
      '.md': 'markdown',
      '.txt': 'text'
    };
    
    return extMap[ext];
  }
  
  private getFileExtension(filePath: string): string {
    const lastDot = filePath.lastIndexOf('.');
    return lastDot > -1 ? filePath.slice(lastDot) : '';
  }
  
  getTokenBudget(totalLimit: number): {
    fileMapTokens: number;
    codeMapTokens: number;
    contentTokens: number;
  } {
    // Allocate token budget
    // 10% for file map (directory structure)
    // 30% for code map (symbol summaries)
    // 60% for actual file contents
    
    return {
      fileMapTokens: Math.floor(totalLimit * 0.1),
      codeMapTokens: Math.floor(totalLimit * 0.3),
      contentTokens: Math.floor(totalLimit * 0.6)
    };
  }
}