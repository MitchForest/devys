import { test, expect, describe, beforeAll, afterAll } from 'bun:test';
import { ParserManager } from '../../src/services/parser/parser-manager';
import { $ } from 'bun';

const TEST_DIR = './test-workspace-parser';

describe('Parser', () => {
  let parser: ParserManager;
  
  beforeAll(async () => {
    parser = new ParserManager();
    
    // Create test workspace with sample files
    await $`mkdir -p ${TEST_DIR}`.quiet();
    
    // TypeScript test file
    await Bun.write(`${TEST_DIR}/test.ts`, `
export interface User {
  id: number;
  name: string;
}

export class UserService {
  async getUser(id: number): Promise<User> {
    return { id, name: 'Test' };
  }
  
  private validateUser(user: User): boolean {
    return user.id > 0;
  }
}

export async function fetchUsers(): Promise<User[]> {
  return [];
}

export const API_KEY = 'secret';
`);
    
    // Python test file
    await Bun.write(`${TEST_DIR}/test.py`, `
class DataProcessor:
    def __init__(self, config):
        self.config = config
    
    def process(self, data):
        if not data:
            return None
        return self._transform(data)
    
    def _transform(self, data):
        return data.upper()

async def fetch_data(url):
    return {"data": "test"}

API_ENDPOINT = "https://api.example.com"
`);
    
    // Rust test file
    await Bun.write(`${TEST_DIR}/test.rs`, `
pub struct Config {
    pub name: String,
    pub port: u16,
}

impl Config {
    pub fn new(name: String) -> Self {
        Config { name, port: 8080 }
    }
}

pub async fn start_server(config: Config) -> Result<(), Error> {
    Ok(())
}

fn internal_helper() -> bool {
    true
}
`);
  });
  
  afterAll(async () => {
    await $`rm -rf ${TEST_DIR}`.quiet();
  });
  
  test('detects language from file extension', () => {
    expect(parser.detectLanguage('file.ts')).toBe('typescript');
    expect(parser.detectLanguage('file.tsx')).toBe('typescript');
    expect(parser.detectLanguage('file.js')).toBe('javascript');
    expect(parser.detectLanguage('file.py')).toBe('python');
    expect(parser.detectLanguage('file.rs')).toBe('rust');
    expect(parser.detectLanguage('file.go')).toBe('go');
    expect(parser.detectLanguage('file.java')).toBe('java');
    expect(parser.detectLanguage('file.txt')).toBe(null);
  });
  
  test('parses TypeScript file and extracts symbols', async () => {
    const result = await parser.parseFile(`${TEST_DIR}/test.ts`);
    
    expect(result.language).toBe('typescript');
    expect(result.symbols.length).toBeGreaterThan(0);
    
    // Check for interface
    const userInterface = result.symbols.find(s => s.name === 'User' && s.kind === 'interface');
    expect(userInterface).toBeDefined();
    expect(userInterface?.exported).toBe(true);
    
    // Check for class
    const userService = result.symbols.find(s => s.name === 'UserService' && s.kind === 'class');
    expect(userService).toBeDefined();
    expect(userService?.exported).toBe(true);
    
    // Check for async function
    const fetchUsers = result.symbols.find(s => s.name === 'fetchUsers' && s.kind === 'function');
    expect(fetchUsers).toBeDefined();
    expect(fetchUsers?.async).toBe(true);
    expect(fetchUsers?.exported).toBe(true);
    
    // Check for const
    const apiKey = result.symbols.find(s => s.name === 'API_KEY' && s.kind === 'variable');
    expect(apiKey).toBeDefined();
    expect(apiKey?.exported).toBe(true);
  });
  
  test('parses Python file and extracts symbols', async () => {
    const result = await parser.parseFile(`${TEST_DIR}/test.py`);
    
    expect(result.language).toBe('python');
    expect(result.symbols.length).toBeGreaterThan(0);
    
    // Check for class
    const dataProcessor = result.symbols.find(s => s.name === 'DataProcessor' && s.kind === 'class');
    expect(dataProcessor).toBeDefined();
    expect(dataProcessor?.exported).toBe(true); // Not starting with _
    
    // Check for async function
    const fetchData = result.symbols.find(s => s.name === 'fetch_data' && s.kind === 'function');
    expect(fetchData).toBeDefined();
    expect(fetchData?.async).toBe(true);
    
    // Check for private method
    const transform = result.symbols.find(s => s.name === '_transform' && s.kind === 'function');
    expect(transform).toBeDefined();
    expect(transform?.exported).toBe(false); // Starts with _
  });
  
  test('parses Rust file and extracts symbols', async () => {
    const result = await parser.parseFile(`${TEST_DIR}/test.rs`);
    
    expect(result.language).toBe('rust');
    expect(result.symbols.length).toBeGreaterThan(0);
    
    // Check for struct
    const config = result.symbols.find(s => s.name === 'Config' && s.kind === 'class');
    expect(config).toBeDefined();
    expect(config?.exported).toBe(true); // Has pub modifier
    
    // Check for async function
    const startServer = result.symbols.find(s => s.name === 'start_server' && s.kind === 'function');
    expect(startServer).toBeDefined();
    expect(startServer?.async).toBe(true);
    expect(startServer?.exported).toBe(true);
    
    // Check for private function
    const helper = result.symbols.find(s => s.name === 'internal_helper' && s.kind === 'function');
    expect(helper).toBeDefined();
    expect(helper?.exported).toBe(false); // No pub modifier
  });
  
  test('calculates complexity correctly', async () => {
    // Create a complex function
    await Bun.write(`${TEST_DIR}/complex.ts`, `
function complexFunction(data: any[]) {
  if (!data) return null;           // +1
  
  for (const item of data) {        // +1
    if (item.type === 'A') {        // +1
      while (item.value > 0) {      // +1
        item.value--;
      }
    } else if (item.type === 'B') { // +1
      try {
        processItem(item);
      } catch (e) {                  // +1
        console.error(e);
      }
    }
  }
  
  return data.length > 0 ? data : null; // +1
}
`);
    
    const result = await parser.parseFile(`${TEST_DIR}/complex.ts`);
    const complexFunc = result.symbols.find(s => s.name === 'complexFunction');
    
    expect(complexFunc).toBeDefined();
    expect(complexFunc?.complexity).toBeGreaterThan(5);
  });
  
  test('handles files with no symbols gracefully', async () => {
    await Bun.write(`${TEST_DIR}/empty.ts`, '// Just comments\n/* No code here */');
    
    const result = await parser.parseFile(`${TEST_DIR}/empty.ts`);
    
    expect(result.language).toBe('typescript');
    expect(result.symbols).toEqual([]);
    expect(result.parseTimeMs).toBeDefined();
  });
  
  test('handles unknown file types', async () => {
    await Bun.write(`${TEST_DIR}/unknown.xyz`, 'Some random content');
    
    const result = await parser.parseFile(`${TEST_DIR}/unknown.xyz`);
    
    expect(result.language).toBe('unknown');
    expect(result.symbols).toEqual([]);
  });
  
  test('parses multiple files in parallel', async () => {
    const files = [
      `${TEST_DIR}/test.ts`,
      `${TEST_DIR}/test.py`,
      `${TEST_DIR}/test.rs`
    ];
    
    const startTime = performance.now();
    const results = await parser.parseFiles(files);
    const duration = performance.now() - startTime;
    
    expect(results.length).toBe(3);
    expect(results.every(r => r.symbols.length > 0)).toBe(true);
    
    // Should be reasonably fast due to parallel processing
    expect(duration).toBeLessThan(1000);
  });
});