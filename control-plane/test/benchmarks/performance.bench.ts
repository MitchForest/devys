import { bench, run } from 'mitata';
import { MerkleTreeBuilder, MerkleTreeDiffer } from '../../src/services/merkle';
import { ParserManager } from '../../src/services/parser/parser-manager';
import { TokenCounter } from '../../src/services/tokens/token-counter';
import { FileSelector } from '../../src/services/selection/file-selector';
import { Database } from 'bun:sqlite';
import { CacheManager } from '../../src/services/cache/cache-manager';
import { ContextGenerator } from '../../src/services/context/context-generator';
import { $ } from 'bun';

// Setup test data
const SMALL_WORKSPACE = './test-workspace-small';  // 10 files
const MEDIUM_WORKSPACE = './test-workspace-medium'; // 100 files
const LARGE_WORKSPACE = './test-workspace-large';   // 1000 files

async function setupTestWorkspaces() {
  // Create small workspace
  await $`mkdir -p ${SMALL_WORKSPACE}/src`.quiet();
  for (let i = 0; i < 10; i++) {
    await Bun.write(`${SMALL_WORKSPACE}/src/file${i}.ts`, generateTypeScriptFile(i));
  }
  
  // Create medium workspace
  await $`mkdir -p ${MEDIUM_WORKSPACE}/src ${MEDIUM_WORKSPACE}/test ${MEDIUM_WORKSPACE}/lib`.quiet();
  for (let i = 0; i < 100; i++) {
    const dir = i < 40 ? 'src' : i < 70 ? 'test' : 'lib';
    await Bun.write(`${MEDIUM_WORKSPACE}/${dir}/file${i}.ts`, generateTypeScriptFile(i));
  }
  
  // Create large workspace
  await $`mkdir -p ${LARGE_WORKSPACE}/src ${LARGE_WORKSPACE}/test ${LARGE_WORKSPACE}/lib ${LARGE_WORKSPACE}/docs`.quiet();
  for (let i = 0; i < 1000; i++) {
    const dir = i < 400 ? 'src' : i < 600 ? 'test' : i < 800 ? 'lib' : 'docs';
    const ext = i % 3 === 0 ? '.ts' : i % 3 === 1 ? '.js' : '.md';
    await Bun.write(`${LARGE_WORKSPACE}/${dir}/file${i}${ext}`, generateFileContent(i, ext));
  }
}

function generateTypeScriptFile(index: number): string {
  return `
export interface Model${index} {
  id: number;
  name: string;
  data: any;
}

export class Service${index} {
  constructor(private config: any) {}
  
  async process(input: Model${index}): Promise<Model${index}> {
    // Processing logic
    if (input.id > 0) {
      return { ...input, data: 'processed' };
    }
    throw new Error('Invalid input');
  }
  
  private validate(model: Model${index}): boolean {
    return model.id > 0 && model.name.length > 0;
  }
}

export function helper${index}(value: number): number {
  return value * 2;
}

export const CONFIG_${index} = {
  timeout: 5000,
  retries: 3
};
`;
}

function generateFileContent(index: number, ext: string): string {
  if (ext === '.md') {
    return `# Documentation ${index}\n\nThis is documentation for module ${index}.\n\n## Usage\n\nExample content here.`;
  }
  return generateTypeScriptFile(index);
}

async function cleanupTestWorkspaces() {
  await $`rm -rf ${SMALL_WORKSPACE} ${MEDIUM_WORKSPACE} ${LARGE_WORKSPACE}`.quiet();
}

// Benchmarks
console.log('🚀 Starting Performance Benchmarks...\n');
console.log('Setting up test workspaces...');
await setupTestWorkspaces();

const db = new Database(':memory:');
const merkleBuilder = new MerkleTreeBuilder();
const merkleDiffer = new MerkleTreeDiffer();
const parserManager = new ParserManager();
const tokenCounter = new TokenCounter();
const cacheManager = new CacheManager(db);

// Benchmark: Merkle Tree Building
bench('Merkle Tree - Build (10 files)', async () => {
  await merkleBuilder.buildTree(SMALL_WORKSPACE);
});

bench('Merkle Tree - Build (100 files)', async () => {
  await merkleBuilder.buildTree(MEDIUM_WORKSPACE);
});

bench('Merkle Tree - Build (1000 files)', async () => {
  await merkleBuilder.buildTree(LARGE_WORKSPACE);
});

// Benchmark: Merkle Tree Diffing
const tree1Small = await merkleBuilder.buildTree(SMALL_WORKSPACE);
await Bun.write(`${SMALL_WORKSPACE}/src/modified.ts`, 'export const modified = true;');
const tree2Small = await merkleBuilder.buildTree(SMALL_WORKSPACE);

bench('Merkle Tree - Diff (10 files, 1 change)', () => {
  merkleDiffer.diff(tree1Small, tree2Small);
});

// Benchmark: Parser
bench('Parser - Parse TypeScript file', async () => {
  await parserManager.parseFile(`${SMALL_WORKSPACE}/src/file0.ts`);
});

bench('Parser - Parse 10 files (parallel)', async () => {
  const files = Array.from({ length: 10 }, (_, i) => `${SMALL_WORKSPACE}/src/file${i}.ts`);
  await parserManager.parseFiles(files);
});

// Benchmark: Token Counting
const sampleText = generateTypeScriptFile(0);
bench('Token Counter - Estimate tokens', () => {
  tokenCounter.estimateTokens(sampleText, 'typescript');
});

bench('Token Counter - Count file', async () => {
  await tokenCounter.countFile(`${SMALL_WORKSPACE}/src/file0.ts`);
});

// Benchmark: File Selection
const fileSelector = new FileSelector(MEDIUM_WORKSPACE);
bench('File Selector - Select with patterns (100 files)', async () => {
  await fileSelector.selectFiles({
    patterns: ['src/**/*.ts'],
    excludePatterns: ['**/*.test.ts'],
    maxFiles: 50
  });
});

// Benchmark: Full Context Generation
const contextGenSmall = new ContextGenerator(SMALL_WORKSPACE, db);
const contextGenMedium = new ContextGenerator(MEDIUM_WORKSPACE, db);
const contextGenLarge = new ContextGenerator(LARGE_WORKSPACE, db);

bench('Context Generation - Small (10 files)', async () => {
  await contextGenSmall.generateContext({ maxTokens: 10000 });
});

bench('Context Generation - Medium (100 files)', async () => {
  await contextGenMedium.generateContext({ maxTokens: 50000 });
});

bench('Context Generation - Large (1000 files)', async () => {
  await contextGenLarge.generateContext({ maxTokens: 100000 });
});

// Benchmark: Cache Performance
bench('Cache - Save Merkle tree', async () => {
  await cacheManager.saveMerkleTree(SMALL_WORKSPACE, 'test-commit', tree1Small);
});

bench('Cache - Retrieve Merkle tree', async () => {
  await cacheManager.getMerkleTree(SMALL_WORKSPACE, 'test-commit');
});

// Run benchmarks
console.log('\nRunning benchmarks...\n');
await run({
  avg: true,
  json: false,
  colors: true,
  min_max: true,
  percentiles: true,
});

// Cleanup
console.log('\nCleaning up test workspaces...');
await cleanupTestWorkspaces();

console.log('\n✅ Benchmarks completed!');

// Performance targets summary
console.log('\n📊 Performance Targets:');
console.log('  • Initial parse (10K files): Target <5s');
console.log('  • Incremental update: Target <100ms');
console.log('  • Merkle diff (100K files): Target <50ms');
console.log('  • Cache retrieval: Target <10ms');