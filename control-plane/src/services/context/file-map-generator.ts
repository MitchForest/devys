import type { FileMap, FileNode, MerkleTree, MerkleNode } from '../../types/context';

export class FileMapGenerator {
  async generate(
    tree: MerkleTree,
    selectedFiles: string[],
    tokenLimit: number
  ): Promise<FileMap> {
    // Convert selected files to a Set for O(1) lookup
    const selectedSet = new Set(this.normalizeFilePaths(selectedFiles, tree.workspace));
    
    // Build file tree structure
    const structure = this.buildFileTree(tree.root, tree.workspace, selectedSet);
    
    // Calculate statistics
    const stats = this.calculateStats(structure);
    
    // Optimize for token limit if necessary
    const optimized = this.optimizeForTokens(structure, tokenLimit);
    
    return {
      structure: optimized,
      totalFiles: stats.totalFiles,
      selectedFiles: stats.selectedFiles,
      languages: stats.languages,
      sizeBytes: stats.sizeBytes
    };
  }
  
  private normalizeFilePaths(files: string[], workspace: string): string[] {
    return files.map(file => {
      if (file.startsWith(workspace)) {
        return file.slice(workspace.length + 1);
      }
      return file;
    });
  }
  
  private buildFileTree(
    node: MerkleNode,
    workspace: string,
    selectedSet: Set<string>,
    parentPath: string = ''
  ): FileNode[] {
    const nodes: FileNode[] = [];
    
    if (node.type === 'file') {
      const fullPath = parentPath ? `${parentPath}/${node.path}` : node.path;
      const selected = selectedSet.has(fullPath);
      
      nodes.push({
        name: node.path.split('/').pop() || node.path,
        path: fullPath,
        type: 'file',
        language: this.detectLanguage(node.path),
        size: node.size,
        selected
      });
    } else if (node.children) {
      // Directory node
      const currentPath = parentPath ? `${parentPath}/${node.path}` : node.path;
      const children: FileNode[] = [];
      
      // Process children
      for (const [name, child] of node.children.entries()) {
        const childNodes = this.buildFileTree(child, workspace, selectedSet, currentPath);
        children.push(...childNodes);
      }
      
      // Only include directories that have children
      if (children.length > 0) {
        // Group by immediate children vs nested
        const immediateChildren: FileNode[] = [];
        const nestedByDir = new Map<string, FileNode[]>();
        
        for (const child of children) {
          const pathParts = child.path.split('/');
          const relativePath = currentPath ? child.path.slice(currentPath.length + 1) : child.path;
          const relativeparts = relativePath.split('/');
          
          if (relativeparts.length === 1) {
            // Direct child
            immediateChildren.push(child);
          } else {
            // Nested - group by immediate subdirectory
            const subdir = relativeparts[0];
            if (!nestedByDir.has(subdir)) {
              nestedByDir.set(subdir, []);
            }
            nestedByDir.get(subdir)!.push(child);
          }
        }
        
        // Add immediate children
        nodes.push(...immediateChildren);
        
        // Create directory nodes for subdirectories
        for (const [dirName, dirChildren] of nestedByDir.entries()) {
          const dirPath = currentPath ? `${currentPath}/${dirName}` : dirName;
          const hasSelectedChildren = dirChildren.some(c => 
            c.type === 'file' ? c.selected : this.hasSelectedDescendant(c)
          );
          
          nodes.push({
            name: dirName,
            path: dirPath,
            type: 'directory',
            selected: hasSelectedChildren,
            children: dirChildren
          });
        }
      }
    }
    
    return nodes;
  }
  
  private hasSelectedDescendant(node: FileNode): boolean {
    if (node.type === 'file') {
      return node.selected;
    }
    
    if (node.children) {
      return node.children.some(child => this.hasSelectedDescendant(child));
    }
    
    return false;
  }
  
  private detectLanguage(filePath: string): string | undefined {
    const ext = filePath.split('.').pop()?.toLowerCase();
    const languageMap: Record<string, string> = {
      'ts': 'TypeScript',
      'tsx': 'TypeScript',
      'js': 'JavaScript',
      'jsx': 'JavaScript',
      'py': 'Python',
      'rs': 'Rust',
      'go': 'Go',
      'java': 'Java',
      'cpp': 'C++',
      'c': 'C',
      'h': 'C',
      'hpp': 'C++',
      'cs': 'C#',
      'rb': 'Ruby',
      'php': 'PHP',
      'swift': 'Swift',
      'kt': 'Kotlin',
      'scala': 'Scala',
      'r': 'R',
      'sql': 'SQL',
      'sh': 'Shell',
      'bash': 'Shell',
      'yaml': 'YAML',
      'yml': 'YAML',
      'json': 'JSON',
      'xml': 'XML',
      'html': 'HTML',
      'css': 'CSS',
      'scss': 'SCSS',
      'less': 'LESS',
      'md': 'Markdown',
      'mdx': 'Markdown',
      'txt': 'Text'
    };
    
    return ext ? languageMap[ext] : undefined;
  }
  
  private calculateStats(nodes: FileNode[]): {
    totalFiles: number;
    selectedFiles: number;
    languages: Map<string, number>;
    sizeBytes: number;
  } {
    let totalFiles = 0;
    let selectedFiles = 0;
    const languages = new Map<string, number>();
    let sizeBytes = 0;
    
    const traverse = (nodeList: FileNode[]) => {
      for (const node of nodeList) {
        if (node.type === 'file') {
          totalFiles++;
          if (node.selected) {
            selectedFiles++;
          }
          if (node.language) {
            languages.set(node.language, (languages.get(node.language) || 0) + 1);
          }
          if (node.size) {
            sizeBytes += node.size;
          }
        } else if (node.children) {
          traverse(node.children);
        }
      }
    };
    
    traverse(nodes);
    
    return {
      totalFiles,
      selectedFiles,
      languages,
      sizeBytes
    };
  }
  
  private optimizeForTokens(nodes: FileNode[], tokenLimit: number): FileNode[] {
    // Estimate current token usage
    const currentTokens = this.estimateTokens(nodes);
    
    if (currentTokens <= tokenLimit) {
      return nodes;
    }
    
    // Need to trim - prioritize selected files and important directories
    return this.trimTree(nodes, tokenLimit);
  }
  
  private estimateTokens(nodes: FileNode[]): number {
    // Rough estimate: each node takes about 10-20 tokens
    let count = 0;
    
    const traverse = (nodeList: FileNode[]) => {
      for (const node of nodeList) {
        count += 15; // Base cost per node
        if (node.children) {
          traverse(node.children);
        }
      }
    };
    
    traverse(nodes);
    return count;
  }
  
  private trimTree(nodes: FileNode[], tokenLimit: number): FileNode[] {
    // Strategy: Keep selected files and their parent directories
    // Remove unselected files from deep directories first
    
    const trimmed: FileNode[] = [];
    const maxDepth = 3; // Maximum directory depth to show
    
    const trimRecursive = (nodeList: FileNode[], depth: number): FileNode[] => {
      const result: FileNode[] = [];
      
      for (const node of nodeList) {
        if (node.type === 'file') {
          // Keep selected files and files at shallow depth
          if (node.selected || depth < 2) {
            result.push(node);
          }
        } else if (node.children && depth < maxDepth) {
          // Recursively trim children
          const trimmedChildren = trimRecursive(node.children, depth + 1);
          if (trimmedChildren.length > 0) {
            result.push({
              ...node,
              children: trimmedChildren
            });
          }
        } else if (node.children) {
          // Too deep - just indicate presence
          result.push({
            ...node,
            children: undefined // Remove children to save tokens
          });
        }
      }
      
      return result;
    };
    
    return trimRecursive(nodes, 0);
  }
}