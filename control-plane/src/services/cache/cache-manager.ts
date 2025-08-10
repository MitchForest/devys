import { Database } from 'bun:sqlite';
import type { 
  MerkleTree, 
  ParsedFile, 
  CodeMap, 
  CacheEntry,
  CacheMetrics 
} from '../../types/context';

export class CacheManager {
  private memory: Map<string, CacheEntry>;
  private db: Database;
  private maxMemorySize: number = 100 * 1024 * 1024; // 100MB
  private currentSize: number = 0;
  
  constructor(db: Database) {
    this.memory = new Map();
    this.db = db;
    this.initializeCache();
  }
  
  private initializeCache() {
    // Run migration for cache tables
    const migration = Bun.file('db/migrations/002_cache_tables.sql');
    migration.text().then(sql => {
      this.db.exec(sql);
    });
  }
  
  async getMerkleTree(workspace: string, commitSha: string): Promise<MerkleTree | null> {
    // Check memory cache
    const memKey = `merkle:${workspace}:${commitSha}`;
    const memEntry = this.memory.get(memKey);
    if (memEntry) {
      this.recordHit('merkle_memory');
      memEntry.hits++;
      memEntry.lastUsed = Date.now();
      return memEntry.data;
    }
    
    // Check disk cache
    const row = this.db.query(
      "SELECT tree_data FROM merkle_cache WHERE workspace = ? AND commit_sha = ?"
    ).get(workspace, commitSha) as any;
    
    if (row) {
      this.recordHit('merkle_disk');
      const tree = JSON.parse(row.tree_data);
      
      // Promote to memory cache
      this.addToMemory(memKey, tree);
      
      return tree;
    }
    
    this.recordMiss('merkle_disk');
    return null;
  }
  
  async saveMerkleTree(workspace: string, commitSha: string, tree: MerkleTree) {
    const memKey = `merkle:${workspace}:${commitSha}`;
    
    // Save to memory
    this.addToMemory(memKey, tree);
    
    // Save to disk
    this.db.run(
      `INSERT OR REPLACE INTO merkle_cache 
       (workspace, commit_sha, tree_data, root_hash, file_count, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [workspace, commitSha, JSON.stringify(tree), tree.root.hash, tree.fileCount, Date.now()]
    );
  }
  
  async getParsedFile(filePath: string, contentHash: string): Promise<ParsedFile | null> {
    const row = this.db.query(
      "SELECT * FROM file_cache WHERE file_path = ? AND content_hash = ?"
    ).get(filePath, contentHash) as any;
    
    if (row) {
      this.recordHit('file_cache');
      return {
        filePath,
        language: row.language,
        symbols: JSON.parse(row.symbols),
        parseTimeMs: row.parse_time_ms
      };
    }
    
    this.recordMiss('file_cache');
    return null;
  }
  
  async saveParsedFile(filePath: string, contentHash: string, parsed: ParsedFile) {
    this.db.run(
      `INSERT OR REPLACE INTO file_cache 
       (file_path, content_hash, symbols, language, parse_time_ms, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        filePath,
        contentHash,
        JSON.stringify(parsed.symbols),
        parsed.language,
        parsed.parseTimeMs || 0,
        Date.now()
      ]
    );
  }
  
  async getCodeMap(workspace: string, stateHash: string): Promise<CodeMap | null> {
    const memKey = `codemap:${workspace}:${stateHash}`;
    const memEntry = this.memory.get(memKey);
    
    if (memEntry) {
      this.recordHit('codemap_cache');
      memEntry.hits++;
      memEntry.lastUsed = Date.now();
      return memEntry.data;
    }
    
    const row = this.db.query(
      "SELECT code_map FROM codemap_cache WHERE workspace = ? AND state_hash = ?"
    ).get(workspace, stateHash) as any;
    
    if (row) {
      this.recordHit('codemap_cache');
      const codeMap = JSON.parse(row.code_map);
      this.addToMemory(memKey, codeMap);
      return codeMap;
    }
    
    this.recordMiss('codemap_cache');
    return null;
  }
  
  async saveCodeMap(workspace: string, stateHash: string, codeMap: CodeMap) {
    const memKey = `codemap:${workspace}:${stateHash}`;
    
    // Save to memory
    this.addToMemory(memKey, codeMap);
    
    // Save to disk
    this.db.run(
      `INSERT OR REPLACE INTO codemap_cache 
       (workspace, state_hash, code_map, file_count, symbol_count, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        workspace,
        stateHash,
        JSON.stringify(codeMap),
        codeMap.byFile.size,
        codeMap.totalSymbols,
        Date.now()
      ]
    );
  }
  
  async invalidateFile(filePath: string) {
    // Remove from file cache
    this.db.run("DELETE FROM file_cache WHERE file_path = ?", [filePath]);
    
    // Remove from memory cache (scan for keys containing file path)
    for (const [key, _] of this.memory) {
      if (key.includes(filePath)) {
        this.memory.delete(key);
      }
    }
  }
  
  async invalidateWorkspace(workspace: string) {
    // Clear merkle cache for workspace
    this.db.run("DELETE FROM merkle_cache WHERE workspace = ?", [workspace]);
    
    // Clear codemap cache for workspace
    this.db.run("DELETE FROM codemap_cache WHERE workspace = ?", [workspace]);
    
    // Clear memory cache for workspace
    for (const [key, _] of this.memory) {
      if (key.includes(workspace)) {
        this.memory.delete(key);
      }
    }
  }
  
  private addToMemory(key: string, data: any) {
    const size = this.estimateSize(data);
    
    // Evict if necessary
    while (this.currentSize + size > this.maxMemorySize && this.memory.size > 0) {
      this.evictLRU();
    }
    
    this.memory.set(key, {
      data,
      size,
      lastUsed: Date.now(),
      hits: 0
    });
    
    this.currentSize += size;
  }
  
  private evictLRU() {
    let oldest: [string, CacheEntry] | null = null;
    
    for (const entry of this.memory.entries()) {
      if (!oldest || entry[1].lastUsed < oldest[1].lastUsed) {
        oldest = entry;
      }
    }
    
    if (oldest) {
      this.memory.delete(oldest[0]);
      this.currentSize -= oldest[1].size;
    }
  }
  
  private estimateSize(data: any): number {
    // Rough estimation of object size in memory
    const str = JSON.stringify(data);
    return str.length * 2; // Assume 2 bytes per character
  }
  
  private recordHit(operation: string) {
    this.db.run(
      `UPDATE cache_metrics 
       SET hit_count = hit_count + 1, last_updated = ?
       WHERE operation = ?`,
      [Date.now(), operation]
    );
  }
  
  private recordMiss(operation: string) {
    this.db.run(
      `UPDATE cache_metrics 
       SET miss_count = miss_count + 1, last_updated = ?
       WHERE operation = ?`,
      [Date.now(), operation]
    );
  }
  
  getMetrics(): CacheMetrics {
    const rows = this.db.query(
      "SELECT operation, hit_count, miss_count FROM cache_metrics"
    ).all() as any[];
    
    let totalHits = 0;
    let totalMisses = 0;
    
    for (const row of rows) {
      totalHits += row.hit_count || 0;
      totalMisses += row.miss_count || 0;
    }
    
    const total = totalHits + totalMisses;
    const hitRate = total > 0 ? (totalHits / total) * 100 : 0;
    
    return {
      hits: totalHits,
      misses: totalMisses,
      hitRate,
      avgResponseTimeMs: 0, // Would need timing logic
      memoryUsageBytes: this.currentSize
    };
  }
  
  clearCache() {
    // Clear memory
    this.memory.clear();
    this.currentSize = 0;
    
    // Clear disk
    this.db.run("DELETE FROM merkle_cache");
    this.db.run("DELETE FROM file_cache");
    this.db.run("DELETE FROM codemap_cache");
    
    // Reset metrics
    this.db.run("UPDATE cache_metrics SET hit_count = 0, miss_count = 0");
  }
}