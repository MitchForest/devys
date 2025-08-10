import { Database } from 'bun:sqlite';
import type { 
  GeneratedContext, 
  SelectionOptions, 
  MerkleTree,
  ParsedFile,
  FileMap,
  CodeMap,
  ContextMetadata,
  FileContent,
  WorkingSet,
  SelectionRules
} from '../../types/context';
import { MerkleTreeBuilder, MerkleTreeDiffer } from '../merkle';
import { CacheManager } from '../cache/cache-manager';
import { ParserManager } from '../parser/parser-manager';
import { FileSelector } from '../selection/file-selector';
import { TokenCounter } from '../tokens/token-counter';
import { ContextScorer } from '../selection/scoring';
import { GitManager } from '../git/git-manager';
import { WorkingSetTracker } from '../git/working-set';
import { FileMapGenerator } from './file-map-generator';
import { CodeMapGenerator } from './code-map-generator';
import { IncrementalUpdater } from '../incremental/file-watcher';

export class ContextGenerator {
  private merkleBuilder: MerkleTreeBuilder;
  private merkleDiffer: MerkleTreeDiffer;
  public cacheManager: CacheManager; // Made public for incremental updates
  private parserManager: ParserManager;
  private fileSelector: FileSelector;
  private tokenCounter: TokenCounter;
  private contextScorer: ContextScorer;
  private gitManager: GitManager;
  private workingSetTracker: WorkingSetTracker;
  private fileMapGenerator: FileMapGenerator;
  private codeMapGenerator: CodeMapGenerator;
  private incrementalUpdater: IncrementalUpdater | null = null;
  
  private previousTree: MerkleTree | null = null;
  
  constructor(
    private workspace: string,
    private db: Database
  ) {
    // Initialize all services
    this.merkleBuilder = new MerkleTreeBuilder();
    this.merkleDiffer = new MerkleTreeDiffer();
    this.cacheManager = new CacheManager(db);
    this.parserManager = new ParserManager();
    this.fileSelector = new FileSelector(workspace);
    this.tokenCounter = new TokenCounter();
    this.contextScorer = new ContextScorer(workspace);
    this.gitManager = new GitManager(workspace);
    this.workingSetTracker = new WorkingSetTracker(workspace);
    this.fileMapGenerator = new FileMapGenerator();
    this.codeMapGenerator = new CodeMapGenerator();
  }
  
  async generateContext(options: SelectionOptions = {}): Promise<GeneratedContext> {
    const startTime = performance.now();
    
    try {
      // Step 1: Build or retrieve Merkle tree
      const currentTree = await this.getCurrentTree();
      
      // Step 2: Get changed files since last generation
      const changedFiles = await this.getChangedFiles(currentTree);
      
      // Step 3: Parse changed files only (with caching)
      const parsedFiles = await this.parseChangedFiles(changedFiles);
      
      // Step 4: Select files based on options
      const selectedFiles = await this.fileSelector.selectFiles(options);
      
      // Step 5: Get working set for scoring
      const workingSet = await this.workingSetTracker.getWorkingSet();
      
      // Step 6: Score and prioritize files
      const scoredFiles = await this.scoreFiles(selectedFiles, workingSet);
      
      // Step 7: Get token budget
      const maxTokens = options.maxTokens || 100000;
      const tokenBudget = this.tokenCounter.getTokenBudget(maxTokens);
      
      // Step 8: Generate file map (lightweight, always included)
      const fileMap = await this.fileMapGenerator.generate(
        currentTree,
        selectedFiles,
        tokenBudget.fileMapTokens
      );
      
      // Step 9: Generate code map (symbol summaries)
      const codeMap = await this.generateCodeMap(
        parsedFiles,
        selectedFiles,
        scoredFiles,
        tokenBudget.codeMapTokens
      );
      
      // Step 10: Select file contents based on remaining tokens
      const selectedContents = await this.selectFileContents(
        selectedFiles,
        scoredFiles,
        tokenBudget.contentTokens
      );
      
      // Step 11: Calculate metadata
      const metadata: ContextMetadata = {
        workspace: this.workspace,
        timestamp: Date.now(),
        commitSha: currentTree.commitSha,
        totalTokens: await this.calculateTotalTokens(fileMap, codeMap, selectedContents),
        fileCount: selectedFiles.length,
        symbolCount: codeMap?.totalSymbols || 0,
        parseTimeMs: performance.now() - startTime,
        cacheHits: this.cacheManager.getMetrics().hits,
        cacheMisses: this.cacheManager.getMetrics().misses
      };
      
      // Store tree for next diff
      this.previousTree = currentTree;
      
      return {
        fileMap,
        codeMap,
        selectedFiles: selectedContents,
        metadata
      };
      
    } catch (error) {
      console.error('Error generating context:', error);
      throw error;
    }
  }
  
  private async getCurrentTree(): Promise<MerkleTree> {
    const commitSha = await this.gitManager.getCurrentCommit();
    
    // Try to get from cache if we have a commit
    if (commitSha) {
      const cachedTree = await this.cacheManager.getMerkleTree(this.workspace, commitSha);
      if (cachedTree) {
        return cachedTree;
      }
    }
    
    // Build new tree
    const tree = await this.merkleBuilder.buildTree(this.workspace);
    
    // Cache it if we have a commit
    if (commitSha && tree.commitSha) {
      await this.cacheManager.saveMerkleTree(this.workspace, commitSha, tree);
    }
    
    return tree;
  }
  
  private async getChangedFiles(currentTree: MerkleTree): Promise<string[]> {
    if (!this.previousTree) {
      // First run - all files are "new"
      return await this.getAllFilePaths(currentTree);
    }
    
    // Diff trees to find changes
    const diff = this.merkleDiffer.diff(this.previousTree, currentTree);
    
    // Return changed files (added + modified)
    return [...diff.added, ...diff.modified];
  }
  
  private async getAllFilePaths(tree: MerkleTree): Promise<string[]> {
    const paths: string[] = [];
    
    const traverse = (node: any, basePath: string = '') => {
      const fullPath = basePath ? `${basePath}/${node.path}` : node.path;
      
      if (node.type === 'file') {
        paths.push(`${this.workspace}/${fullPath}`);
      } else if (node.children) {
        for (const [name, child] of node.children.entries()) {
          traverse(child, fullPath);
        }
      }
    };
    
    traverse(tree.root);
    return paths;
  }
  
  private async parseChangedFiles(filePaths: string[]): Promise<Map<string, ParsedFile>> {
    const parsed = new Map<string, ParsedFile>();
    
    // Parse files in parallel with caching
    const parsePromises = filePaths.map(async filePath => {
      // Check cache first
      const file = Bun.file(filePath);
      const content = await file.text();
      const contentHash = await this.hashContent(content);
      
      let parsedFile = await this.cacheManager.getParsedFile(filePath, contentHash);
      
      if (!parsedFile) {
        // Parse and cache
        parsedFile = await this.parserManager.parseFile(filePath);
        await this.cacheManager.saveParsedFile(filePath, contentHash, parsedFile);
      }
      
      parsed.set(filePath, parsedFile);
    });
    
    await Promise.all(parsePromises);
    return parsed;
  }
  
  private async hashContent(content: string): Promise<string> {
    const hasher = new Bun.CryptoHasher('sha256');
    hasher.update(content);
    return hasher.digest('hex');
  }
  
  private async scoreFiles(
    filePaths: string[],
    workingSet: WorkingSet
  ): Promise<Map<string, number>> {
    const scores = new Map<string, number>();
    const rules = this.contextScorer.getDefaultRules();
    
    const scorePromises = filePaths.map(async filePath => {
      const score = await this.contextScorer.scoreFile(filePath, rules, workingSet);
      scores.set(filePath, score);
    });
    
    await Promise.all(scorePromises);
    return scores;
  }
  
  private async generateCodeMap(
    parsedFiles: Map<string, ParsedFile>,
    selectedFiles: string[],
    fileScores: Map<string, number>,
    tokenLimit: number
  ): Promise<CodeMap> {
    // Filter parsed files to only selected ones
    const relevantParsed = new Map<string, ParsedFile>();
    for (const file of selectedFiles) {
      const parsed = parsedFiles.get(file);
      if (parsed) {
        relevantParsed.set(file, parsed);
      }
    }
    
    // Generate code map with scoring
    return await this.codeMapGenerator.generate(
      relevantParsed,
      fileScores,
      tokenLimit
    );
  }
  
  private async selectFileContents(
    filePaths: string[],
    fileScores: Map<string, number>,
    tokenLimit: number
  ): Promise<FileContent[]> {
    // Count tokens for each file
    const tokenCounts = await this.tokenCounter.countFiles(filePaths);
    
    // Optimize selection based on scores and token limits
    const selectedPaths = this.tokenCounter.optimizeForLimit(
      tokenCounts,
      tokenLimit,
      fileScores
    );
    
    // Load file contents
    const contents: FileContent[] = [];
    for (const path of selectedPaths) {
      const file = Bun.file(path);
      const content = await file.text();
      const language = this.detectLanguage(path);
      const tokens = tokenCounts.get(path) || 0;
      
      contents.push({
        path,
        content,
        language: language || 'unknown',
        tokens
      });
    }
    
    return contents;
  }
  
  private detectLanguage(filePath: string): string | null {
    return this.parserManager.detectLanguage(filePath);
  }
  
  private async calculateTotalTokens(
    fileMap: FileMap,
    codeMap: CodeMap | undefined,
    contents: FileContent[]
  ): Promise<number> {
    // Estimate tokens for file map (usually small)
    const fileMapTokens = Math.ceil(JSON.stringify(fileMap).length / 10);
    
    // Estimate tokens for code map
    const codeMapTokens = codeMap 
      ? Math.ceil(JSON.stringify(codeMap).length / 8)
      : 0;
    
    // Sum content tokens
    const contentTokens = contents.reduce((sum, f) => sum + f.tokens, 0);
    
    return fileMapTokens + codeMapTokens + contentTokens;
  }
  
  async updateContext(trigger: string, data?: any): Promise<GeneratedContext> {
    // Handle different triggers
    switch (trigger) {
      case 'file_save':
        // Invalidate cache for saved file
        if (data?.filePath) {
          await this.cacheManager.invalidateFile(data.filePath);
        }
        break;
        
      case 'git_commit':
        // Clear workspace cache on commit
        await this.cacheManager.invalidateWorkspace(this.workspace);
        break;
        
      case 'file_open':
        // Track file as opened
        if (data?.filePath) {
          this.workingSetTracker.trackFileOpen(data.filePath);
        }
        break;
        
      case 'file_close':
        // Track file as closed
        if (data?.filePath) {
          this.workingSetTracker.trackFileClose(data.filePath);
        }
        break;
    }
    
    // Regenerate context with same options
    return this.generateContext();
  }
  
  getMetrics() {
    return {
      cacheMetrics: this.cacheManager.getMetrics(),
      workspace: this.workspace,
      treeSize: this.previousTree?.fileCount || 0
    };
  }
  
  clearCache() {
    this.cacheManager.clearCache();
    this.previousTree = null;
  }
  
  // Incremental update methods
  enableIncrementalUpdates() {
    if (!this.incrementalUpdater) {
      this.incrementalUpdater = new IncrementalUpdater(this.workspace, this);
      
      // Listen for context updates
      this.incrementalUpdater.on('context-updated', (event) => {
        console.log('Context updated:', event.files.length, 'files changed');
      });
      
      this.incrementalUpdater.on('error', (error) => {
        console.error('Incremental update error:', error);
      });
    }
    
    this.incrementalUpdater.start();
  }
  
  disableIncrementalUpdates() {
    if (this.incrementalUpdater) {
      this.incrementalUpdater.stop();
    }
  }
  
  isWatchingFiles(): boolean {
    return this.incrementalUpdater?.isRunning() || false;
  }
}