import { minimatch } from 'minimatch';

export async function computeHash(data: string | ArrayBuffer | Uint8Array): Promise<string> {
  const hasher = new Bun.CryptoHasher('sha256');
  
  if (typeof data === 'string') {
    hasher.update(data);
  } else if (data instanceof ArrayBuffer) {
    hasher.update(new Uint8Array(data));
  } else {
    hasher.update(data);
  }
  
  return hasher.digest('hex');
}

export function shouldIgnore(path: string, patterns: string[]): boolean {
  for (const pattern of patterns) {
    if (minimatch(path, pattern, { dot: true })) {
      return true;
    }
    // Also check if path starts with pattern (for directories)
    if (path === pattern || path.startsWith(pattern + '/')) {
      return true;
    }
  }
  return false;
}

export function countFiles(node: import('../../types/context').MerkleNode): number {
  if (node.type === 'file') {
    return 1;
  }
  
  let count = 0;
  if (node.children) {
    for (const child of node.children.values()) {
      count += countFiles(child);
    }
  }
  return count;
}

export function collectAllPaths(
  node: import('../../types/context').MerkleNode,
  basePath: string = ''
): string[] {
  const paths: string[] = [];
  const fullPath = basePath ? `${basePath}/${node.path}` : node.path;
  
  if (node.type === 'file') {
    paths.push(fullPath);
  } else if (node.children) {
    for (const [name, child] of node.children.entries()) {
      paths.push(...collectAllPaths(child, fullPath));
    }
  }
  
  return paths;
}