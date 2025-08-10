import type { MerkleTree, MerkleNode, TreeDiff } from '../../types/context';
import { countFiles, collectAllPaths } from './hash-utils';

export class MerkleTreeDiffer {
  diff(oldTree: MerkleTree, newTree: MerkleTree): TreeDiff {
    const result: TreeDiff = {
      added: [],
      modified: [],
      deleted: [],
      unchanged: 0
    };
    
    this.compareNodes(oldTree.root, newTree.root, result);
    return result;
  }
  
  private compareNodes(
    oldNode: MerkleNode | undefined,
    newNode: MerkleNode | undefined,
    result: TreeDiff,
    parentPath: string = ''
  ) {
    // Node added
    if (!oldNode && newNode) {
      const paths = collectAllPaths(newNode, parentPath);
      result.added.push(...paths.filter(p => !p.endsWith('/')));
      return;
    }
    
    // Node deleted
    if (oldNode && !newNode) {
      const paths = collectAllPaths(oldNode, parentPath);
      result.deleted.push(...paths.filter(p => !p.endsWith('/')));
      return;
    }
    
    // Both exist - compare hashes
    if (oldNode && newNode) {
      // Quick check: if hashes match, entire subtree is unchanged
      if (oldNode.hash === newNode.hash) {
        result.unchanged += countFiles(oldNode);
        return;
      }
      
      // Hash different - need to dig deeper
      const currentPath = parentPath ? `${parentPath}/${newNode.path}` : newNode.path;
      
      if (newNode.type === 'file') {
        // File modified
        result.modified.push(currentPath);
      } else {
        // Directory changed - compare children
        const oldChildren = oldNode.children || new Map();
        const newChildren = newNode.children || new Map();
        
        const allKeys = new Set([...oldChildren.keys(), ...newChildren.keys()]);
        
        for (const key of allKeys) {
          this.compareNodes(
            oldChildren.get(key),
            newChildren.get(key),
            result,
            currentPath
          );
        }
      }
    }
  }
  
  getChangeStats(diff: TreeDiff): {
    totalChanges: number;
    changeRate: number;
    summary: string;
  } {
    const totalChanges = diff.added.length + diff.modified.length + diff.deleted.length;
    const totalFiles = totalChanges + diff.unchanged;
    const changeRate = totalFiles > 0 ? (totalChanges / totalFiles) * 100 : 0;
    
    return {
      totalChanges,
      changeRate,
      summary: `Added: ${diff.added.length}, Modified: ${diff.modified.length}, Deleted: ${diff.deleted.length}, Unchanged: ${diff.unchanged}`
    };
  }
  
  filterByExtension(diff: TreeDiff, extensions: string[]): TreeDiff {
    const matchesExtension = (path: string) => {
      return extensions.some(ext => path.endsWith(ext));
    };
    
    return {
      added: diff.added.filter(matchesExtension),
      modified: diff.modified.filter(matchesExtension),
      deleted: diff.deleted.filter(matchesExtension),
      unchanged: diff.unchanged
    };
  }
}