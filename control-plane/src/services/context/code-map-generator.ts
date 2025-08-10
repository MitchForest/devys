import type {
  CodeMap,
  ParsedFile,
  ExtractedSymbol,
  FunctionSummary,
  ClassSummary,
  InterfaceSummary,
  TypeSummary,
  ImportSummary,
  ExportSummary,
  SymbolSummary
} from '../../types/context';

export class CodeMapGenerator {
  async generate(
    parsedFiles: Map<string, ParsedFile>,
    fileScores: Map<string, number>,
    tokenLimit: number
  ): Promise<CodeMap> {
    const functions: FunctionSummary[] = [];
    const classes: ClassSummary[] = [];
    const interfaces: InterfaceSummary[] = [];
    const types: TypeSummary[] = [];
    const imports: ImportSummary[] = [];
    const exports: ExportSummary[] = [];
    
    const byFile = new Map<string, SymbolSummary[]>();
    const byKind = new Map<string, SymbolSummary[]>();
    const languages = new Map<string, number>();
    
    // Process each parsed file
    for (const [filePath, parsedFile] of parsedFiles.entries()) {
      const fileScore = fileScores.get(filePath) || 0;
      const fileSymbols: SymbolSummary[] = [];
      
      // Count language
      if (parsedFile.language) {
        languages.set(parsedFile.language, (languages.get(parsedFile.language) || 0) + 1);
      }
      
      // Process symbols
      for (const symbol of parsedFile.symbols) {
        const summary = this.createSymbolSummary(symbol, filePath, fileScore);
        
        if (!summary) continue;
        
        // Add to appropriate category
        switch (symbol.kind) {
          case 'function':
          case 'method':
            const funcSummary = summary as FunctionSummary;
            functions.push(funcSummary);
            fileSymbols.push(funcSummary);
            break;
            
          case 'class':
            const classSummary = this.enhanceClassSummary(summary as ClassSummary, parsedFile);
            classes.push(classSummary);
            fileSymbols.push(classSummary);
            break;
            
          case 'interface':
            const interfaceSummary = this.enhanceInterfaceSummary(summary as InterfaceSummary, parsedFile);
            interfaces.push(interfaceSummary);
            fileSymbols.push(interfaceSummary);
            break;
            
          case 'type':
            const typeSummary = summary as TypeSummary;
            types.push(typeSummary);
            fileSymbols.push(typeSummary);
            break;
        }
        
        // Add to byKind map
        if (!byKind.has(symbol.kind)) {
          byKind.set(symbol.kind, []);
        }
        byKind.get(symbol.kind)!.push(summary);
      }
      
      // Store symbols by file
      if (fileSymbols.length > 0) {
        byFile.set(filePath, fileSymbols);
      }
    }
    
    // Sort by importance score
    functions.sort((a, b) => (b.importanceScore || 0) - (a.importanceScore || 0));
    classes.sort((a, b) => (b.importanceScore || 0) - (a.importanceScore || 0));
    interfaces.sort((a, b) => (b.importanceScore || 0) - (a.importanceScore || 0));
    types.sort((a, b) => (b.importanceScore || 0) - (a.importanceScore || 0));
    
    // Optimize for token limit
    const optimized = this.optimizeForTokenLimit(
      { functions, classes, interfaces, types },
      tokenLimit
    );
    
    return {
      functions: optimized.functions,
      classes: optimized.classes,
      interfaces: optimized.interfaces,
      types: optimized.types,
      imports,
      exports,
      byFile,
      byKind,
      totalSymbols: optimized.functions.length + 
                   optimized.classes.length + 
                   optimized.interfaces.length + 
                   optimized.types.length,
      languages
    };
  }
  
  private createSymbolSummary(
    symbol: ExtractedSymbol,
    filePath: string,
    fileScore: number
  ): SymbolSummary | null {
    const baseScore = this.calculateImportanceScore(symbol, fileScore);
    
    switch (symbol.kind) {
      case 'function':
      case 'method':
        return {
          name: symbol.name,
          signature: symbol.signature || `${symbol.name}()`,
          file: filePath,
          line: symbol.line,
          complexity: symbol.complexity || 1,
          exported: symbol.exported,
          async: symbol.async || false,
          importanceScore: baseScore
        } as FunctionSummary;
        
      case 'class':
        return {
          name: symbol.name,
          file: filePath,
          line: symbol.line,
          exported: symbol.exported,
          methods: [], // Will be enhanced later
          properties: [], // Will be enhanced later
          importanceScore: baseScore
        } as ClassSummary;
        
      case 'interface':
        return {
          name: symbol.name,
          file: filePath,
          line: symbol.line,
          exported: symbol.exported,
          properties: [], // Will be enhanced later
          methods: [], // Will be enhanced later
          importanceScore: baseScore
        } as InterfaceSummary;
        
      case 'type':
        return {
          name: symbol.name,
          definition: symbol.signature || symbol.name,
          file: filePath,
          line: symbol.line,
          exported: symbol.exported,
          importanceScore: baseScore
        } as TypeSummary;
        
      default:
        return null;
    }
  }
  
  private calculateImportanceScore(symbol: ExtractedSymbol, fileScore: number): number {
    let score = fileScore;
    
    // Exported symbols are more important
    if (symbol.exported) {
      score += 20;
    }
    
    // Complex symbols need attention
    if (symbol.complexity && symbol.complexity > 5) {
      score += symbol.complexity * 2;
    }
    
    // Entry point functions
    if (symbol.name === 'main' || symbol.name === 'init' || symbol.name === 'start') {
      score += 30;
    }
    
    // Test functions are less important
    if (symbol.name.includes('test') || symbol.name.includes('spec')) {
      score -= 10;
    }
    
    return Math.max(score, 0);
  }
  
  private enhanceClassSummary(summary: ClassSummary, parsedFile: ParsedFile): ClassSummary {
    // Extract methods and properties for the class
    // This is simplified - real implementation would use AST
    const methods: string[] = [];
    const properties: string[] = [];
    
    // Find symbols that belong to this class (simplified heuristic)
    for (const symbol of parsedFile.symbols) {
      if (symbol.kind === 'method' && symbol.line > summary.line && symbol.line < summary.line + 50) {
        methods.push(symbol.signature || symbol.name);
      }
    }
    
    return {
      ...summary,
      methods: methods.slice(0, 10), // Limit to 10 most important
      properties: properties.slice(0, 10)
    };
  }
  
  private enhanceInterfaceSummary(summary: InterfaceSummary, parsedFile: ParsedFile): InterfaceSummary {
    // Similar to class enhancement
    return {
      ...summary,
      properties: [],
      methods: []
    };
  }
  
  private optimizeForTokenLimit(
    symbols: {
      functions: FunctionSummary[];
      classes: ClassSummary[];
      interfaces: InterfaceSummary[];
      types: TypeSummary[];
    },
    tokenLimit: number
  ): typeof symbols {
    // Estimate tokens per symbol type
    const tokensPerFunction = 15;
    const tokensPerClass = 25;
    const tokensPerInterface = 20;
    const tokensPerType = 10;
    
    let currentTokens = 
      symbols.functions.length * tokensPerFunction +
      symbols.classes.length * tokensPerClass +
      symbols.interfaces.length * tokensPerInterface +
      symbols.types.length * tokensPerType;
    
    if (currentTokens <= tokenLimit) {
      return symbols;
    }
    
    // Need to trim - keep highest scoring symbols
    const ratio = tokenLimit / currentTokens;
    
    return {
      functions: symbols.functions.slice(0, Math.floor(symbols.functions.length * ratio)),
      classes: symbols.classes.slice(0, Math.floor(symbols.classes.length * ratio)),
      interfaces: symbols.interfaces.slice(0, Math.floor(symbols.interfaces.length * ratio)),
      types: symbols.types.slice(0, Math.floor(symbols.types.length * ratio))
    };
  }
}