import type { Tree, SyntaxNode } from 'tree-sitter';
import type { ExtractedSymbol } from '../../types/context';

export class SymbolExtractor {
  constructor(private language: string) {}
  
  extractSymbols(tree: Tree, content: string, filePath: string): ExtractedSymbol[] {
    const symbols: ExtractedSymbol[] = [];
    const rootNode = tree.rootNode;
    
    this.walkTree(rootNode, content, symbols, filePath);
    return symbols;
  }
  
  private walkTree(
    node: SyntaxNode, 
    content: string, 
    symbols: ExtractedSymbol[],
    filePath: string
  ) {
    // Extract based on node type and language
    const symbol = this.extractSymbolFromNode(node, content, filePath);
    if (symbol) {
      symbols.push(symbol);
    }
    
    // Recursively walk children
    for (let i = 0; i < node.childCount; i++) {
      const child = node.child(i);
      if (child) {
        this.walkTree(child, content, symbols, filePath);
      }
    }
  }
  
  private extractSymbolFromNode(
    node: SyntaxNode,
    content: string,
    filePath: string
  ): ExtractedSymbol | null {
    const nodeType = node.type;
    
    // Language-specific extraction
    switch (this.language) {
      case 'typescript':
      case 'javascript':
        return this.extractTypeScriptSymbol(node, content, filePath);
      case 'python':
        return this.extractPythonSymbol(node, content, filePath);
      case 'rust':
        return this.extractRustSymbol(node, content, filePath);
      case 'go':
        return this.extractGoSymbol(node, content, filePath);
      case 'java':
        return this.extractJavaSymbol(node, content, filePath);
      default:
        return null;
    }
  }
  
  private extractTypeScriptSymbol(
    node: SyntaxNode,
    content: string,
    filePath: string
  ): ExtractedSymbol | null {
    const nodeType = node.type;
    
    // Function declarations
    if (nodeType === 'function_declaration' || nodeType === 'method_definition') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const signature = this.extractSignature(node, content);
      const isAsync = this.hasChildOfType(node, 'async');
      const isExported = this.isExported(node);
      
      return {
        name,
        kind: nodeType === 'method_definition' ? 'method' : 'function',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        signature,
        complexity: this.calculateComplexity(node),
        exported: isExported,
        async: isAsync,
        file: filePath
      };
    }
    
    // Class declarations
    if (nodeType === 'class_declaration') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const isExported = this.isExported(node);
      
      return {
        name,
        kind: 'class',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        exported: isExported,
        complexity: this.calculateComplexity(node),
        file: filePath
      };
    }
    
    // Interface declarations
    if (nodeType === 'interface_declaration') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const isExported = this.isExported(node);
      
      return {
        name,
        kind: 'interface',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        exported: isExported,
        file: filePath
      };
    }
    
    // Type aliases
    if (nodeType === 'type_alias_declaration') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const isExported = this.isExported(node);
      
      return {
        name,
        kind: 'type',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        exported: isExported,
        file: filePath
      };
    }
    
    // Variable declarations (const, let, var)
    if (nodeType === 'lexical_declaration' || nodeType === 'variable_declaration') {
      // Find the first variable declarator
      for (let i = 0; i < node.childCount; i++) {
        const child = node.child(i);
        if (child && child.type === 'variable_declarator') {
          const nameNode = child.childForFieldName('name');
          if (!nameNode) continue;
          
          const name = content.slice(nameNode.startIndex, nameNode.endIndex);
          const isExported = this.isExported(node);
          
          return {
            name,
            kind: 'variable',
            line: node.startPosition.row + 1,
            column: node.startPosition.column + 1,
            endLine: node.endPosition.row + 1,
            endColumn: node.endPosition.column + 1,
            exported: isExported,
            file: filePath
          };
        }
      }
    }
    
    return null;
  }
  
  private extractPythonSymbol(
    node: SyntaxNode,
    content: string,
    filePath: string
  ): ExtractedSymbol | null {
    const nodeType = node.type;
    
    // Function definitions
    if (nodeType === 'function_definition') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const signature = this.extractSignature(node, content);
      const isAsync = node.text.startsWith('async ');
      
      return {
        name,
        kind: 'function',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        signature,
        complexity: this.calculateComplexity(node),
        exported: !name.startsWith('_'),
        async: isAsync,
        file: filePath
      };
    }
    
    // Class definitions
    if (nodeType === 'class_definition') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      
      return {
        name,
        kind: 'class',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        exported: !name.startsWith('_'),
        complexity: this.calculateComplexity(node),
        file: filePath
      };
    }
    
    return null;
  }
  
  private extractRustSymbol(
    node: SyntaxNode,
    content: string,
    filePath: string
  ): ExtractedSymbol | null {
    const nodeType = node.type;
    
    // Function items
    if (nodeType === 'function_item') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const signature = this.extractSignature(node, content);
      const isAsync = node.text.includes('async ');
      const isPublic = node.text.startsWith('pub ');
      
      return {
        name,
        kind: 'function',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        signature,
        complexity: this.calculateComplexity(node),
        exported: isPublic,
        async: isAsync,
        file: filePath
      };
    }
    
    // Struct items
    if (nodeType === 'struct_item') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const isPublic = node.text.startsWith('pub ');
      
      return {
        name,
        kind: 'class', // Using 'class' for structs
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        exported: isPublic,
        complexity: 1,
        file: filePath
      };
    }
    
    // Enum items
    if (nodeType === 'enum_item') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const isPublic = node.text.startsWith('pub ');
      
      return {
        name,
        kind: 'enum',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        exported: isPublic,
        file: filePath
      };
    }
    
    return null;
  }
  
  private extractGoSymbol(
    node: SyntaxNode,
    content: string,
    filePath: string
  ): ExtractedSymbol | null {
    const nodeType = node.type;
    
    // Function declarations
    if (nodeType === 'function_declaration' || nodeType === 'method_declaration') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const signature = this.extractSignature(node, content);
      const isExported = name[0] === name[0].toUpperCase();
      
      return {
        name,
        kind: nodeType === 'method_declaration' ? 'method' : 'function',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        signature,
        complexity: this.calculateComplexity(node),
        exported: isExported,
        file: filePath
      };
    }
    
    // Type declarations
    if (nodeType === 'type_declaration') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const isExported = name[0] === name[0].toUpperCase();
      
      return {
        name,
        kind: 'type',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        exported: isExported,
        file: filePath
      };
    }
    
    return null;
  }
  
  private extractJavaSymbol(
    node: SyntaxNode,
    content: string,
    filePath: string
  ): ExtractedSymbol | null {
    const nodeType = node.type;
    
    // Method declarations
    if (nodeType === 'method_declaration') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const signature = this.extractSignature(node, content);
      const isPublic = node.text.includes('public ');
      
      return {
        name,
        kind: 'method',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        signature,
        complexity: this.calculateComplexity(node),
        exported: isPublic,
        file: filePath
      };
    }
    
    // Class declarations
    if (nodeType === 'class_declaration') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const isPublic = node.text.includes('public ');
      
      return {
        name,
        kind: 'class',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        exported: isPublic,
        complexity: this.calculateComplexity(node),
        file: filePath
      };
    }
    
    // Interface declarations
    if (nodeType === 'interface_declaration') {
      const nameNode = node.childForFieldName('name');
      if (!nameNode) return null;
      
      const name = content.slice(nameNode.startIndex, nameNode.endIndex);
      const isPublic = node.text.includes('public ');
      
      return {
        name,
        kind: 'interface',
        line: node.startPosition.row + 1,
        column: node.startPosition.column + 1,
        endLine: node.endPosition.row + 1,
        endColumn: node.endPosition.column + 1,
        exported: isPublic,
        file: filePath
      };
    }
    
    return null;
  }
  
  private extractSignature(node: SyntaxNode, content: string): string {
    // Extract just the signature part (before the body)
    const bodyNode = node.childForFieldName('body');
    if (bodyNode) {
      const signatureEnd = bodyNode.startIndex;
      const signatureStart = node.startIndex;
      return content.slice(signatureStart, signatureEnd).trim();
    }
    
    // If no body, return the first line
    const firstLineEnd = content.indexOf('\n', node.startIndex);
    if (firstLineEnd > -1) {
      return content.slice(node.startIndex, firstLineEnd).trim();
    }
    
    return content.slice(node.startIndex, node.endIndex).trim();
  }
  
  private calculateComplexity(node: SyntaxNode): number {
    let complexity = 1;
    
    // Count decision points
    const decisionTypes = new Set([
      'if_statement',
      'switch_statement',
      'for_statement',
      'while_statement',
      'do_statement',
      'catch_clause',
      'conditional_expression',
      'binary_expression', // for && and ||
    ]);
    
    this.walkForComplexity(node, decisionTypes, (n) => {
      if (decisionTypes.has(n.type)) {
        complexity++;
      }
      // Additional complexity for logical operators
      if (n.type === 'binary_expression') {
        const op = n.childForFieldName('operator');
        if (op && (op.text === '&&' || op.text === '||')) {
          complexity++;
        }
      }
    });
    
    return complexity;
  }
  
  private walkForComplexity(
    node: SyntaxNode,
    types: Set<string>,
    callback: (node: SyntaxNode) => void
  ) {
    callback(node);
    for (let i = 0; i < node.childCount; i++) {
      const child = node.child(i);
      if (child) {
        this.walkForComplexity(child, types, callback);
      }
    }
  }
  
  private hasChildOfType(node: SyntaxNode, type: string): boolean {
    for (let i = 0; i < node.childCount; i++) {
      const child = node.child(i);
      if (child && child.type === type) {
        return true;
      }
    }
    return false;
  }
  
  private isExported(node: SyntaxNode): boolean {
    // Check if node has export modifier
    const parent = node.parent;
    if (parent && parent.type === 'export_statement') {
      return true;
    }
    
    // Check for export keyword in text
    const text = node.text;
    return text.startsWith('export ') || text.includes(' export ');
  }
}