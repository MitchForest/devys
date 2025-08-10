import Parser from 'tree-sitter';
import TypeScript from 'tree-sitter-typescript';
import Python from 'tree-sitter-python';
import Rust from 'tree-sitter-rust';
import Go from 'tree-sitter-go';
import Java from 'tree-sitter-java';
import type { ParsedFile, ExtractedSymbol } from '../../types/context';
import { SymbolExtractor } from './symbol-extractor';

export interface ParserConfig {
  language: string;
  parser: Parser;
  extensions: string[];
  symbolExtractor: SymbolExtractor;
}

export class ParserManager {
  private parsers: Map<string, ParserConfig> = new Map();
  private extensionMap: Map<string, string> = new Map();
  
  constructor() {
    this.initializeParsers();
  }
  
  private initializeParsers() {
    // TypeScript/JavaScript
    this.registerParser('typescript', {
      language: 'typescript',
      parser: this.createParser(TypeScript.tsx),
      extensions: ['.ts', '.tsx', '.mts', '.cts'],
      symbolExtractor: new SymbolExtractor('typescript')
    });
    
    this.registerParser('javascript', {
      language: 'javascript',
      parser: this.createParser(TypeScript.tsx),
      extensions: ['.js', '.jsx', '.mjs', '.cjs'],
      symbolExtractor: new SymbolExtractor('javascript')
    });
    
    // Python
    this.registerParser('python', {
      language: 'python',
      parser: this.createParser(Python),
      extensions: ['.py', '.pyi'],
      symbolExtractor: new SymbolExtractor('python')
    });
    
    // Rust
    this.registerParser('rust', {
      language: 'rust',
      parser: this.createParser(Rust),
      extensions: ['.rs'],
      symbolExtractor: new SymbolExtractor('rust')
    });
    
    // Go
    this.registerParser('go', {
      language: 'go',
      parser: this.createParser(Go),
      extensions: ['.go'],
      symbolExtractor: new SymbolExtractor('go')
    });
    
    // Java
    this.registerParser('java', {
      language: 'java',
      parser: this.createParser(Java),
      extensions: ['.java'],
      symbolExtractor: new SymbolExtractor('java')
    });
  }
  
  private createParser(language: any): Parser {
    const parser = new Parser();
    parser.setLanguage(language);
    return parser;
  }
  
  private registerParser(name: string, config: ParserConfig) {
    this.parsers.set(name, config);
    // Map extensions to language
    for (const ext of config.extensions) {
      this.extensionMap.set(ext, name);
    }
  }
  
  detectLanguage(filePath: string): string | null {
    const ext = this.getFileExtension(filePath);
    return this.extensionMap.get(ext) || null;
  }
  
  private getFileExtension(filePath: string): string {
    const lastDot = filePath.lastIndexOf('.');
    return lastDot > -1 ? filePath.slice(lastDot) : '';
  }
  
  async parseFile(filePath: string): Promise<ParsedFile> {
    const startTime = performance.now();
    const language = this.detectLanguage(filePath);
    
    if (!language) {
      return {
        filePath,
        language: 'unknown',
        symbols: [],
        parseTimeMs: performance.now() - startTime
      };
    }
    
    const config = this.parsers.get(language);
    if (!config) {
      return {
        filePath,
        language,
        symbols: [],
        parseTimeMs: performance.now() - startTime
      };
    }
    
    // Read file content
    const file = Bun.file(filePath);
    const content = await file.text();
    
    // Parse with tree-sitter
    const tree = config.parser.parse(content);
    
    // Extract symbols
    const symbols = config.symbolExtractor.extractSymbols(
      tree,
      content,
      filePath
    );
    
    return {
      filePath,
      language,
      tree,
      content,
      symbols,
      parseTimeMs: performance.now() - startTime
    };
  }
  
  async parseFiles(filePaths: string[]): Promise<ParsedFile[]> {
    const results = await Promise.all(
      filePaths.map(path => this.parseFile(path))
    );
    return results;
  }
  
  getSupportedLanguages(): string[] {
    return Array.from(this.parsers.keys());
  }
  
  getSupportedExtensions(): string[] {
    return Array.from(this.extensionMap.keys());
  }
}