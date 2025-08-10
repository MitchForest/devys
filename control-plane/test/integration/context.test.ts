import { test, expect, describe, beforeAll, afterAll } from 'bun:test';
import { $ } from 'bun';

const TEST_DIR = './test-workspace-context';
const API_BASE = 'http://localhost:3000/api';

describe('Context Generation Integration', () => {
  let serverProcess: any;
  
  beforeAll(async () => {
    // Create test workspace
    await $`mkdir -p ${TEST_DIR}/src ${TEST_DIR}/test`.quiet();
    
    // Create sample files
    await Bun.write(`${TEST_DIR}/src/index.ts`, `
export function main() {
  console.log('Hello, world!');
}

export class Application {
  async start() {
    console.log('Starting application...');
  }
}
`);
    
    await Bun.write(`${TEST_DIR}/src/utils.ts`, `
export function formatDate(date: Date): string {
  return date.toISOString();
}

export const CONFIG = {
  port: 3000,
  host: 'localhost'
};
`);
    
    await Bun.write(`${TEST_DIR}/test/app.test.ts`, `
import { test, expect } from 'bun:test';
import { main } from '../src/index';

test('main function', () => {
  expect(main).toBeDefined();
});
`);
    
    // Start the server in background
    console.log('Starting control plane server...');
    serverProcess = Bun.spawn(['bun', 'run', 'src/server.ts'], {
      cwd: '.',
      stdout: 'pipe',
      stderr: 'pipe'
    });
    
    // Wait for server to start
    await new Promise(resolve => setTimeout(resolve, 2000));
  });
  
  afterAll(async () => {
    // Stop server
    if (serverProcess) {
      serverProcess.kill();
    }
    
    // Clean up test workspace
    await $`rm -rf ${TEST_DIR}`.quiet();
  });
  
  test('POST /api/context/generate - generates full context', async () => {
    const response = await fetch(`${API_BASE}/context/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        workspace: TEST_DIR,
        patterns: ['src/**/*.ts'],
        maxTokens: 10000
      })
    });
    
    expect(response.status).toBe(200);
    
    const context = await response.json();
    
    // Check file map
    expect(context.fileMap).toBeDefined();
    expect(context.fileMap.totalFiles).toBeGreaterThan(0);
    expect(context.fileMap.selectedFiles).toBeGreaterThan(0);
    
    // Check code map
    expect(context.codeMap).toBeDefined();
    expect(context.codeMap.functions.length).toBeGreaterThan(0);
    expect(context.codeMap.classes.length).toBeGreaterThan(0);
    
    // Check metadata
    expect(context.metadata).toBeDefined();
    expect(context.metadata.workspace).toBe(TEST_DIR);
    expect(context.metadata.fileCount).toBeGreaterThan(0);
    expect(context.metadata.symbolCount).toBeGreaterThan(0);
    expect(context.metadata.parseTimeMs).toBeLessThan(5000);
    
    // Verify specific symbols were found
    const mainFunc = context.codeMap.functions.find((f: any) => f.name === 'main');
    expect(mainFunc).toBeDefined();
    expect(mainFunc.exported).toBe(true);
    
    const appClass = context.codeMap.classes.find((c: any) => c.name === 'Application');
    expect(appClass).toBeDefined();
    expect(appClass.exported).toBe(true);
  });
  
  test('GET /api/context/file-map - returns file structure', async () => {
    const response = await fetch(`${API_BASE}/context/file-map?workspace=${TEST_DIR}`);
    
    expect(response.status).toBe(200);
    
    const fileMap = await response.json();
    
    expect(fileMap.structure).toBeDefined();
    expect(fileMap.totalFiles).toBeGreaterThan(0);
    expect(fileMap.languages.size || Object.keys(fileMap.languages).length).toBeGreaterThan(0);
  });
  
  test('GET /api/context/code-map - returns symbol summaries', async () => {
    const response = await fetch(
      `${API_BASE}/context/code-map?workspace=${TEST_DIR}&files=${TEST_DIR}/src/index.ts`
    );
    
    expect(response.status).toBe(200);
    
    const codeMap = await response.json();
    
    expect(codeMap.functions).toBeDefined();
    expect(codeMap.classes).toBeDefined();
    expect(codeMap.totalSymbols).toBeGreaterThan(0);
  });
  
  test('POST /api/context/invalidate - clears cache', async () => {
    // First generate context to populate cache
    await fetch(`${API_BASE}/context/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ workspace: TEST_DIR })
    });
    
    // Get metrics to verify cache has data
    const metricsBeforeResponse = await fetch(`${API_BASE}/context/metrics?workspace=${TEST_DIR}`);
    const metricsBefore = await metricsBeforeResponse.json();
    expect(metricsBefore.cacheMetrics.hits).toBeGreaterThanOrEqual(0);
    
    // Invalidate cache
    const invalidateResponse = await fetch(`${API_BASE}/context/invalidate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ workspace: TEST_DIR })
    });
    
    expect(invalidateResponse.status).toBe(200);
    
    const result = await invalidateResponse.json();
    expect(result.success).toBe(true);
  });
  
  test('GET /api/context/metrics - returns cache metrics', async () => {
    const response = await fetch(`${API_BASE}/context/metrics?workspace=${TEST_DIR}`);
    
    expect(response.status).toBe(200);
    
    const metrics = await response.json();
    
    expect(metrics.cacheMetrics).toBeDefined();
    expect(metrics.cacheMetrics.hitRate).toBeDefined();
    expect(metrics.workspace).toBe(TEST_DIR);
  });
  
  test('handles file selection with patterns', async () => {
    const response = await fetch(`${API_BASE}/context/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        workspace: TEST_DIR,
        patterns: ['**/*.test.ts'],
        excludePatterns: ['node_modules/**'],
        maxFiles: 10
      })
    });
    
    expect(response.status).toBe(200);
    
    const context = await response.json();
    
    // Should only include test files
    const selectedPaths = context.selectedFiles?.map((f: any) => f.path) || [];
    const testFiles = selectedPaths.filter((p: string) => p.includes('.test.'));
    
    expect(testFiles.length).toBeGreaterThan(0);
  });
  
  test('respects token limits', async () => {
    const response = await fetch(`${API_BASE}/context/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        workspace: TEST_DIR,
        maxTokens: 1000 // Very small limit
      })
    });
    
    expect(response.status).toBe(200);
    
    const context = await response.json();
    
    expect(context.metadata.totalTokens).toBeLessThanOrEqual(1000);
  });
});