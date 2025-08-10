# Phase 2: Context Intelligence Layer - Canonical Implementation Guide

## Executive Summary

Phase 2 implements the context intelligence layer that powers AI-assisted development through sophisticated file selection, stored prompt management, and multi-model context optimization. The system leverages Merkle tree-based incremental parsing with git-aware caching to achieve sub-100ms context generation for massive repositories. This layer seamlessly integrates with claude-code-router to provide consistent context across all AI models (Claude, GPT-4, Gemini, DeepSeek, etc.).

## Core Objectives

1. **Intelligent File Selection**: Manual and AI-driven file/folder selection with smart defaults
2. **Stored Prompt Management**: Reusable system instructions and templates
3. **Context Composition**: Optimal assembly of file maps, code maps, and file contents
4. **Agent-Specific Formatting**: Tailored context for planner vs editor agents
5. **Performance at Scale**: Merkle trees + git caching for instant updates

## System Architecture

```
User Intent Layer
┌─────────────────────────────────────────────────────────┐
│  File/Folder Selection → Stored Prompts → Query Input   │
└────────────────────┬────────────────────────────────────┘
                     │
Context Intelligence Layer (Phase 2)
┌────────────────────▼────────────────────────────────────┐
│  ┌─────────────────────────────────────────────────┐   │
│  │           Merkle Tree Change Detector           │   │
│  │  • O(log n) diff detection                      │   │
│  │  • Git commit-based caching                     │   │
│  │  • File hash persistence                        │   │
│  └────────────────┬────────────────────────────────┘   │
│                   │                                     │
│  ┌────────────────▼────────────────────────────────┐   │
│  │           Tree-sitter Symbol Extraction         │   │
│  │  • AST parsing for 5+ languages                 │   │
│  │  • Incremental parsing (changed files only)     │   │
│  │  • Symbol importance ranking                    │   │
│  └────────────────┬────────────────────────────────┘   │
│                   │                                     │
│  ┌────────────────▼────────────────────────────────┐   │
│  │           Context Assembly Pipeline             │   │
│  │  • File Map generation                          │   │
│  │  • Code Map extraction                          │   │
│  │  • Token counting & optimization                │   │
│  │  • Model-specific limits                        │   │
│  └────────────────┬────────────────────────────────┘   │
│                   │                                     │
│  ┌────────────────▼────────────────────────────────┐   │
│  │           Agent-Specific Formatting             │   │
│  │  • Planner: Full context with file contents     │   │
│  │  • Editor: Code maps + specific instructions    │   │
│  │  • Reviewer: Diffs + context                    │   │
│  └────────────────┬────────────────────────────────┘   │
└────────────────────┬────────────────────────────────────┘
                     │
Model Router Layer
┌────────────────────▼────────────────────────────────────┐
│        Claude Code Router (existing integration)         │
│  • Routes to optimal model based on task               │
│  • Maintains consistent tool usage across providers     │
└─────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 2.1: Merkle Tree Foundation (Days 1-3)

#### Core Components

**1. Merkle Tree Manager**
- Build tree structure of file hashes for entire workspace
- Cache trees per git commit (immutable reference)
- Compute diff between trees in O(log n) time
- Persist file hashes to SQLite for resumability

**2. Git-Aware Cache**
- Key all caches by commit SHA
- Share cache across all sessions at same commit
- Instant branch switching (just load different cache)
- Automatic cache invalidation on new commits

**3. Change Detection Pipeline**
```
Current State → Build Merkle Tree → Compare with Cached Tree
                                  ↓
                        Changed Files List
                                  ↓
                    Parse Only Changed Files
                                  ↓
                    Update Code Maps Incrementally
```

#### Database Schema
```sql
-- Merkle tree cache
CREATE TABLE merkle_trees (
  workspace TEXT,
  commit_sha TEXT,
  root_hash TEXT NOT NULL,
  tree_data BLOB NOT NULL,
  file_count INTEGER,
  timestamp INTEGER,
  PRIMARY KEY (workspace, commit_sha)
);

-- File-level cache
CREATE TABLE file_cache (
  file_path TEXT,
  content_hash TEXT,
  commit_sha TEXT,
  parsed_ast BLOB,
  symbols TEXT, -- JSON
  last_parsed INTEGER,
  PRIMARY KEY (file_path, content_hash)
);

-- Performance metrics
CREATE TABLE parse_metrics (
  workspace TEXT,
  operation TEXT,
  duration_ms REAL,
  files_processed INTEGER,
  cache_hits INTEGER,
  timestamp INTEGER
);
```

### Phase 2.2: Tree-sitter Integration (Days 4-6)

#### Language Support
- TypeScript/JavaScript (`.ts`, `.tsx`, `.js`, `.jsx`)
- Python (`.py`, `.pyi`)
- Rust (`.rs`)
- Go (`.go`)
- Java (`.java`)

#### Symbol Extraction Pipeline

**1. Parser Manager**
- Initialize language-specific parsers
- Load tree-sitter queries for each language
- Cache parsed ASTs by file hash

**2. Symbol Extractor**
- Extract functions, classes, interfaces, types
- Calculate complexity scores (cyclomatic complexity)
- Track symbol relationships (imports, exports, calls)
- Rank symbols by importance

**3. Code Map Generator**
```typescript
interface CodeMap {
  // High-level structure without implementation
  functions: Array<{
    name: string;
    signature: string;
    file: string;
    line: number;
    complexity: number;
  }>;
  
  classes: Array<{
    name: string;
    methods: string[];
    file: string;
    line: number;
  }>;
  
  interfaces: Array<{
    name: string;
    properties: string[];
    file: string;
    line: number;
  }>;
  
  imports: Array<{
    from: string;
    to: string;
    symbols: string[];
  }>;
}
```

#### Tree-sitter Queries
```scheme
; TypeScript symbols.scm
(function_declaration
  name: (identifier) @function.name) @function

(class_declaration
  name: (type_identifier) @class.name) @class

(interface_declaration
  name: (type_identifier) @interface.name) @interface

(import_statement
  source: (string) @import.source) @import
```

### Phase 2.3: Context Selection Engine (Days 7-9)

#### Selection Strategies

**1. Manual Selection**
- User selects specific files/folders
- Support for glob patterns
- `.aiignore` file support (like `.gitignore`)
- Quick selection presets (working set, recent, related)

**2. Smart Selection Rules**
```typescript
interface SelectionRules {
  maxTokens: number;          // Model-specific limit
  priorityWeights: {
    exported: 20;            // Public API surface
    recent: 15;              // Recently modified
    complex: 10;             // High complexity
    referenced: 10;          // Frequently imported
    tested: 5;               // Has tests
  };
  
  taskSpecific: {
    debugging: {
      includeTests: true;
      includeErrors: true;
      recencyBoost: 2.0;
    };
    refactoring: {
      includeRelated: true;
      complexityBoost: 2.0;
    };
    documentation: {
      includePublicOnly: true;
      includeComments: true;
    };
  };
}
```

**3. Working Set Tracking**
- Open files in editor (from Helix buffers)
- Recently modified files (git status)
- Files in current git diff
- Files mentioned in recent commits

#### Token Optimization

**1. Model Limits**
```typescript
const MODEL_LIMITS = {
  'claude-3-opus': { context: 200000, output: 4096 },
  'claude-3-sonnet': { context: 200000, output: 4096 },
  'gpt-4-turbo': { context: 128000, output: 4096 },
  'gpt-4o': { context: 128000, output: 4096 },
  'gemini-1.5-pro': { context: 2000000, output: 8192 },
  'deepseek-v2': { context: 128000, output: 4096 }
};
```

**2. Optimization Strategies**
- Include full content for important files
- Fall back to code maps for less important files
- Remove comments and whitespace if needed
- Truncate with ellipsis for very large files
- Prioritize based on selection rules

### Phase 2.4: Stored Prompt Management (Days 10-11)

#### Prompt Storage System

**1. Prompt Types**
```typescript
interface StoredPrompt {
  id: string;
  name: string;
  description: string;
  type: 'system' | 'task' | 'agent';
  content: string;
  variables?: Record<string, string>;
  tags: string[];
  created: number;
  updated: number;
  usage_count: number;
}
```

**2. Default Agent Prompts**
```yaml
planner:
  name: "Planner Agent"
  type: "agent"
  content: |
    You are a strategic planner. Analyze the entire codebase context and create 
    a comprehensive, step-by-step plan. Consider dependencies, test coverage, 
    and potential impacts. Your plan should be executable by another agent.

editor:
  name: "Editor Agent"  
  type: "agent"
  content: |
    You are a precise code editor. Follow the provided plan exactly. Make 
    minimal, targeted changes. Preserve code style and maintain compatibility.
    The plan is in {plan_file} and the context includes relevant code maps.

reviewer:
  name: "Reviewer Agent"
  type: "agent"
  content: |
    You are a meticulous code reviewer. Analyze changes for bugs, security 
    issues, and best practices. Consider the broader context and impacts.
```

**3. Variable Interpolation**
```typescript
function interpolatePrompt(prompt: StoredPrompt, context: any): string {
  let content = prompt.content;
  
  // Replace variables like {workspace}, {task_type}, {plan_file}
  for (const [key, value] of Object.entries(context)) {
    content = content.replace(new RegExp(`{${key}}`, 'g'), value);
  }
  
  return content;
}
```

### Phase 2.5: Context Assembly Pipeline (Days 12-13)

#### Assembly Process

**1. File Map Generation**
```typescript
interface FileMap {
  structure: {
    path: string;
    type: 'file' | 'directory';
    language?: string;
    size: number;
    symbols?: number;
    selected: boolean;
    children?: FileMap[];
  };
  
  stats: {
    totalFiles: number;
    selectedFiles: number;
    totalLines: number;
    languages: Record<string, number>;
  };
}
```

**2. Context Assembly Order**
```
1. System Instructions (from stored prompts)
   ↓
2. User Query (specific instructions)
   ↓
3. File Map (structure overview)
   ↓
4. Code Maps (if enabled, symbol summaries)
   ↓
5. File Contents (actual code, optimized for tokens)
```

**3. Agent-Specific Formatting**

**Planner Agent Context:**
```markdown
## System Instructions
[Stored prompt content]

## Task
[User's specific query]

## Repository Structure
[Complete file map]

## Code Overview
[Code maps with all symbols]

## Selected Files
[Full file contents]
```

**Editor Agent Context:**
```markdown
## System Instructions
[Stored prompt content]

## Execution Plan
[Reference to plan file: plans/task-001.md]

## Relevant Code Maps
[Only symbols mentioned in plan]

## Working Files
[Specific files to edit, no extras]
```

### Phase 2.6: Performance Optimization (Days 14-15)

#### Caching Strategy

**1. Multi-Level Cache**
```
Memory Cache (Hot Data)
  ├── Recent parse results
  ├── Active file maps
  └── Current context
  
SQLite Cache (Warm Data)
  ├── File hashes by commit
  ├── Parsed ASTs
  └── Generated code maps
  
Git Object Store (Cold Data)
  └── Historical contexts by commit
```

**2. Cache Invalidation**
```typescript
class CacheInvalidator {
  async invalidate(trigger: CacheTrigger) {
    switch (trigger.type) {
      case 'file_save':
        // Invalidate single file
        await this.invalidateFile(trigger.file);
        break;
        
      case 'git_commit':
        // New commit = new cache namespace
        await this.createNewCacheNamespace(trigger.commit);
        break;
        
      case 'branch_switch':
        // Load different cache namespace
        await this.switchCacheNamespace(trigger.branch);
        break;
    }
  }
}
```

**3. Performance Targets**
- Initial parse: < 5s for 10K files
- Incremental update: < 100ms for single file
- Context assembly: < 500ms for 100 files
- Cache hit rate: > 90% for unchanged files

### Phase 2.7: Integration Points (Days 16-17)

#### 1. Control Plane Integration

**New API Endpoints:**
```typescript
// Generate context with options
POST /api/context/generate
{
  workspace: string;
  selectedFiles?: string[];
  selectedFolders?: string[];
  storedPromptId?: string;
  query: string;
  agent: 'planner' | 'editor' | 'reviewer';
  model?: string;
}

// Manage stored prompts
GET /api/prompts
POST /api/prompts
PUT /api/prompts/:id
DELETE /api/prompts/:id

// Get file/code maps
GET /api/context/file-map?workspace=...
GET /api/context/code-map?workspace=...&files=...

// Invalidate cache
POST /api/context/invalidate
{
  workspace: string;
  reason: 'file_save' | 'git_commit' | 'manual';
}
```

#### 2. Claude Code CLI Integration

**Context Flow:**
```bash
# User invokes planner agent
claude --agent planner "Create a REST API for user management"

# Our system:
1. Detects agent type (planner)
2. Loads planner stored prompt
3. Generates file map of workspace
4. Selects relevant files (models, routes, controllers)
5. Generates code maps for selected files
6. Assembles context with full file contents
7. Sends to claude-code-router
8. Router selects model (e.g., Gemini for large context)
9. Returns comprehensive plan

# User invokes editor agent
claude --agent editor --plan plans/user-api.md

# Our system:
1. Detects agent type (editor)
2. Loads editor stored prompt
3. Reads plan file
4. Extracts mentioned files from plan
5. Generates focused context (code maps only)
6. Sends to claude-code-router
7. Router selects model (e.g., Claude for precision)
8. Executes plan with file edits
```

#### 3. Helix Editor Integration

**Key Bindings:**
```toml
[keys.normal]
# Context commands
"space c" = {
  s = ":sh context-select"      # Interactive file selection
  g = ":sh context-generate"    # Generate current context
  p = ":sh context-prompt"      # Select stored prompt
  v = ":sh context-view"        # View assembled context
  c = ":sh context-clear"       # Clear selection
}

# Agent commands  
"space a" = {
  p = ":sh claude --agent planner"   # Planner agent
  e = ":sh claude --agent editor"     # Editor agent
  r = ":sh claude --agent reviewer"   # Reviewer agent
}
```

### Phase 2.8: Testing & Validation (Days 18-19)

#### Test Coverage Requirements

**1. Unit Tests**
- Merkle tree construction and diffing
- Tree-sitter parsing for each language
- Symbol extraction accuracy
- Token counting precision
- Cache hit/miss scenarios

**2. Integration Tests**
- End-to-end context generation
- Multi-file selection scenarios
- Agent-specific formatting
- Cache invalidation flows
- Git integration (commit, branch switch)

**3. Performance Tests**
```typescript
describe("Performance Benchmarks", () => {
  test("10K file repo - cold start < 5s", async () => {
    const start = performance.now();
    await contextService.generateContext(largeRepo);
    expect(performance.now() - start).toBeLessThan(5000);
  });
  
  test("10K file repo - warm cache < 100ms", async () => {
    await contextService.generateContext(largeRepo); // warm up
    
    const start = performance.now();
    await contextService.generateContext(largeRepo);
    expect(performance.now() - start).toBeLessThan(100);
  });
  
  test("Single file change < 100ms", async () => {
    await contextService.generateContext(workspace);
    await fs.writeFile(testFile, newContent);
    
    const start = performance.now();
    await contextService.generateContext(workspace);
    expect(performance.now() - start).toBeLessThan(100);
  });
});
```

## Success Metrics

### Performance KPIs
- ✅ Cold start: < 5s for 10K files
- ✅ Warm cache: < 100ms for unchanged repos
- ✅ Incremental update: < 100ms per file change
- ✅ Context assembly: < 500ms for 100 files
- ✅ Memory usage: < 500MB for large repos
- ✅ Cache hit rate: > 90%

### Functionality KPIs
- ✅ 5+ languages supported
- ✅ Accurate symbol extraction
- ✅ Working git integration
- ✅ Agent-specific formatting
- ✅ Token optimization within limits

### Quality KPIs
- ✅ Test coverage > 80%
- ✅ Zero memory leaks
- ✅ Graceful degradation
- ✅ Clear error messages

## Implementation Timeline

| Day | Focus Area | Deliverables |
|-----|------------|--------------|
| 1-3 | Merkle Trees | Hash tree construction, git caching, diff algorithm |
| 4-6 | Tree-sitter | Parser setup, symbol extraction, incremental parsing |
| 7-9 | Selection Engine | File selection, rules engine, token optimization |
| 10-11 | Stored Prompts | Prompt management, variable interpolation |
| 12-13 | Context Assembly | File maps, code maps, agent formatting |
| 14-15 | Performance | Caching layers, optimization, benchmarking |
| 16-17 | Integration | API endpoints, CLI commands, editor bindings |
| 18-19 | Testing | Unit tests, integration tests, performance validation |

## Risk Mitigation

| Risk | Impact | Mitigation Strategy |
|------|--------|-------------------|
| Merkle tree complexity | High | Start with simple hash comparison, optimize later |
| Tree-sitter performance | High | Aggressive caching, parse only changed files |
| Token counting accuracy | Medium | Use official tokenizers, extensive testing |
| Git integration issues | Medium | Fallback to timestamp-based change detection |
| Memory usage | Medium | Streaming for large files, LRU cache eviction |

## Dependencies

```json
{
  "dependencies": {
    "tree-sitter": "^0.20.0",
    "tree-sitter-typescript": "^0.20.0",
    "tree-sitter-javascript": "^0.20.0",
    "tree-sitter-python": "^0.20.0",
    "tree-sitter-rust": "^0.20.0",
    "tree-sitter-go": "^0.20.0",
    "tree-sitter-java": "^0.20.0",
    "@anthropic/tokenizer": "^0.0.4",
    "tiktoken": "^1.0.0",
    "simple-git": "^3.0.0",
    "crypto": "builtin",
    "zod": "^3.0.0"
  }
}
```

## Configuration Files

### .aiignore Format
```gitignore
# Ignore patterns for AI context
node_modules/
dist/
build/
*.log
*.tmp
.env*
coverage/
.git/

# Include specific files even if parent is ignored
!src/important.ts
```

### Context Configuration
```yaml
# .ai/context.yaml
selection:
  maxTokens: 100000
  includeTests: false
  includeDocumentation: true
  
priorities:
  exported: 20
  recent: 15
  complex: 10
  referenced: 10
  
agents:
  planner:
    model: "gemini-1.5-pro"  # Large context
    includeEverything: true
    
  editor:
    model: "claude-3-opus"    # Precision
    includeCodeMapsOnly: true
    
  reviewer:
    model: "gpt-4o"          # Reasoning
    includeDiffs: true
```

## Monitoring & Observability

### Metrics to Track
```typescript
interface ContextMetrics {
  // Performance
  parseTime: number;
  cacheHitRate: number;
  contextAssemblyTime: number;
  
  // Usage
  filesSelected: number;
  tokensGenerated: number;
  modelUsed: string;
  
  // Quality
  symbolsExtracted: number;
  errorsEncountered: number;
  truncationsRequired: number;
}
```

### Logging Strategy
```typescript
logger.info('context.generation.started', {
  workspace,
  agent,
  selectedFiles: files.length,
  model
});

logger.debug('merkle.tree.diff', {
  changed: changedFiles.length,
  total: totalFiles,
  time: diffTime
});

logger.warn('context.truncation', {
  original: originalTokens,
  truncated: truncatedTokens,
  model
});
```

## Phase 2 Completion Criteria

### Must Have
- [ ] Merkle tree change detection working
- [ ] Git-aware caching implemented
- [ ] 5+ languages parsing correctly
- [ ] File selection UI functional
- [ ] Stored prompts CRUD operations
- [ ] Agent-specific context formatting
- [ ] Token optimization within limits
- [ ] Integration with claude-code-router

### Should Have
- [ ] .aiignore file support
- [ ] Context preview before sending
- [ ] Performance benchmarks passing
- [ ] 80%+ test coverage
- [ ] Monitoring dashboard

### Nice to Have
- [ ] AI-driven file selection (future)
- [ ] Context templates library
- [ ] Multi-workspace support
- [ ] Context sharing between users

---

*This document serves as the canonical reference for Phase 2 implementation. All development should align with these specifications. Any deviations require explicit approval and documentation updates.*