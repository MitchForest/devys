import { test, expect, describe, beforeAll, afterAll } from 'bun:test';
import { MerkleTreeBuilder, MerkleTreeDiffer } from '../../src/services/merkle';
import { $ } from 'bun';

const TEST_DIR = './test-workspace-merkle';

describe('MerkleTree', () => {
  let builder: MerkleTreeBuilder;
  let differ: MerkleTreeDiffer;
  
  beforeAll(async () => {
    builder = new MerkleTreeBuilder();
    differ = new MerkleTreeDiffer();
    
    // Create test workspace
    await $`mkdir -p ${TEST_DIR}/src ${TEST_DIR}/test`.quiet();
    
    // Create test files
    await Bun.write(`${TEST_DIR}/README.md`, '# Test Project');
    await Bun.write(`${TEST_DIR}/src/index.ts`, 'console.log("hello");');
    await Bun.write(`${TEST_DIR}/src/utils.ts`, 'export const util = () => {};');
    await Bun.write(`${TEST_DIR}/test/test.ts`, 'test("sample", () => {});');
  });
  
  afterAll(async () => {
    // Clean up
    await $`rm -rf ${TEST_DIR}`.quiet();
  });
  
  test('builds tree correctly', async () => {
    const tree = await builder.buildTree(TEST_DIR);
    
    expect(tree.root.type).toBe('directory');
    expect(tree.fileCount).toBe(4);
    expect(tree.workspace).toBe(TEST_DIR);
    expect(tree.timestamp).toBeGreaterThan(0);
  });
  
  test('hash stability - same content produces same hash', async () => {
    const tree1 = await builder.buildTree(TEST_DIR);
    const tree2 = await builder.buildTree(TEST_DIR);
    
    expect(tree1.root.hash).toBe(tree2.root.hash);
    expect(tree1.fileCount).toBe(tree2.fileCount);
  });
  
  test('detects file changes', async () => {
    const tree1 = await builder.buildTree(TEST_DIR);
    
    // Modify a file
    await Bun.write(`${TEST_DIR}/src/index.ts`, 'console.log("modified");');
    
    const tree2 = await builder.buildTree(TEST_DIR);
    
    // Hashes should be different
    expect(tree1.root.hash).not.toBe(tree2.root.hash);
    
    // Diff should show the change
    const diff = differ.diff(tree1, tree2);
    expect(diff.modified.length).toBe(1);
    expect(diff.modified[0]).toContain('index.ts');
    expect(diff.added.length).toBe(0);
    expect(diff.deleted.length).toBe(0);
  });
  
  test('detects file additions', async () => {
    const tree1 = await builder.buildTree(TEST_DIR);
    
    // Add a new file
    await Bun.write(`${TEST_DIR}/src/new-file.ts`, 'export const newFile = true;');
    
    const tree2 = await builder.buildTree(TEST_DIR);
    
    const diff = differ.diff(tree1, tree2);
    expect(diff.added.length).toBe(1);
    expect(diff.added[0]).toContain('new-file.ts');
    expect(diff.modified.length).toBe(0);
  });
  
  test('detects file deletions', async () => {
    // Create a file to delete
    const tempFile = `${TEST_DIR}/temp.txt`;
    await Bun.write(tempFile, 'temporary');
    
    const tree1 = await builder.buildTree(TEST_DIR);
    
    // Delete the file
    await $`rm ${tempFile}`.quiet();
    
    const tree2 = await builder.buildTree(TEST_DIR);
    
    const diff = differ.diff(tree1, tree2);
    expect(diff.deleted.length).toBe(1);
    expect(diff.deleted[0]).toContain('temp.txt');
  });
  
  test('ignores specified patterns', async () => {
    // Create files that should be ignored
    await $`mkdir -p ${TEST_DIR}/node_modules`.quiet();
    await Bun.write(`${TEST_DIR}/node_modules/package.json`, '{}');
    await Bun.write(`${TEST_DIR}/.env`, 'SECRET=value');
    
    const tree = await builder.buildTree(TEST_DIR);
    
    // Convert tree to paths to check
    const collectPaths = (node: any, basePath = ''): string[] => {
      const paths: string[] = [];
      if (node.type === 'file') {
        paths.push(node.path);
      } else if (node.children) {
        for (const [name, child] of node.children.entries()) {
          paths.push(...collectPaths(child, basePath ? `${basePath}/${name}` : name));
        }
      }
      return paths;
    };
    
    const allPaths = collectPaths(tree.root);
    
    // Should not include ignored files
    expect(allPaths.some(p => p.includes('node_modules'))).toBe(false);
    expect(allPaths.some(p => p.includes('.env'))).toBe(false);
  });
  
  test('diff performance for large changes', async () => {
    const tree1 = await builder.buildTree(TEST_DIR);
    
    // Make multiple changes
    await Bun.write(`${TEST_DIR}/src/index.ts`, 'console.log("changed");');
    await Bun.write(`${TEST_DIR}/src/utils.ts`, 'export const util = () => { return 1; };');
    await Bun.write(`${TEST_DIR}/src/new1.ts`, 'new file 1');
    await Bun.write(`${TEST_DIR}/src/new2.ts`, 'new file 2');
    
    const tree2 = await builder.buildTree(TEST_DIR);
    
    const startTime = performance.now();
    const diff = differ.diff(tree1, tree2);
    const diffTime = performance.now() - startTime;
    
    // Should be very fast (< 10ms for small trees)
    expect(diffTime).toBeLessThan(10);
    
    // Should correctly identify all changes
    expect(diff.modified.length).toBe(2);
    expect(diff.added.length).toBe(2);
    
    const stats = differ.getChangeStats(diff);
    expect(stats.totalChanges).toBe(4);
  });
});