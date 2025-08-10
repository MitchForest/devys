import type { MerkleNode, MerkleTree } from '../../types/context';
import { computeHash, shouldIgnore } from './hash-utils';
import { $ } from 'bun';

export class MerkleTreeBuilder {
  private fileCount: number = 0;
  private ignorePatterns: string[] = [
    '.git',
    'node_modules',
    'target',
    'dist',
    'build',
    '.DS_Store',
    '*.log',
    '.env*'
  ];

  async buildTree(workspace: string): Promise<MerkleTree> {
    this.fileCount = 0;
    const root = await this.buildNode(workspace, workspace);
    const commitSha = await this.getGitCommit(workspace);
    
    return {
      root,
      workspace,
      commitSha,
      timestamp: Date.now(),
      fileCount: this.fileCount
    };
  }

  private async buildNode(path: string, rootPath: string): Promise<MerkleNode> {
    const file = Bun.file(path);
    const stats = await file.stat();
    const relativePath = this.getRelativePath(rootPath, path);
    
    if (stats.isDirectory()) {
      const entries = await this.readDirectory(path);
      const children = new Map<string, MerkleNode>();
      const childHashes: string[] = [];
      
      // Filter and process entries in parallel
      const filteredEntries = entries.filter(entry => !shouldIgnore(entry, this.ignorePatterns));
      
      const childPromises = filteredEntries.map(async entry => {
        const childPath = `${path}/${entry}`;
        const childNode = await this.buildNode(childPath, rootPath);
        return { entry, childNode };
      });
      
      const childResults = await Promise.all(childPromises);
      
      // Sort results for consistent hashing
      childResults.sort((a, b) => a.entry.localeCompare(b.entry));
      
      for (const { entry, childNode } of childResults) {
        children.set(entry, childNode);
        childHashes.push(`${entry}:${childNode.hash}`);
      }
      
      // Directory hash = hash of sorted child hashes
      const dirContent = childHashes.join('\n');
      const dirHash = await computeHash(dirContent);
      
      return {
        hash: dirHash,
        path: relativePath,
        type: 'directory',
        children
      };
    } else {
      // File hash = hash of content + metadata
      const file = Bun.file(path);
      const content = await file.arrayBuffer();
      const metadata = `${relativePath}:${stats.size}:${stats.mtime.getTime()}`;
      const combinedData = new Uint8Array(content.byteLength + metadata.length);
      
      // Combine content and metadata
      combinedData.set(new Uint8Array(content), 0);
      combinedData.set(new TextEncoder().encode(metadata), content.byteLength);
      
      const fileHash = await computeHash(combinedData);
      this.fileCount++;
      
      return {
        hash: fileHash,
        path: relativePath,
        type: 'file',
        size: stats.size,
        modified: stats.mtime.getTime()
      };
    }
  }

  private async getGitCommit(workspace: string): Promise<string | undefined> {
    try {
      const result = await $`cd ${workspace} && git rev-parse HEAD`.quiet();
      return result.text().trim();
    } catch {
      // Not a git repo or no commits
      return undefined;
    }
  }

  setIgnorePatterns(patterns: string[]) {
    this.ignorePatterns = patterns;
  }

  addIgnorePattern(pattern: string) {
    this.ignorePatterns.push(pattern);
  }

  getFileCount(): number {
    return this.fileCount;
  }

  private async readDirectory(path: string): Promise<string[]> {
    const proc = await $`ls -1 ${path}`.quiet();
    return proc.text().trim().split('\n').filter(Boolean);
  }

  private getRelativePath(rootPath: string, path: string): string {
    if (path === rootPath) return '.';
    if (path.startsWith(rootPath + '/')) {
      return path.slice(rootPath.length + 1);
    }
    return path;
  }
}