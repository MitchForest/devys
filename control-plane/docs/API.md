# Context Intelligence API Documentation

## Overview

The Context Intelligence API provides high-performance code analysis and context generation for software repositories. Built on Phase 2 of the Devys architecture, it offers sub-100ms incremental updates and intelligent file selection.

## Base URL

```
http://localhost:3000/api/context
```

## Authentication

Currently no authentication required (will be added in Phase 4).

## Endpoints

### 1. Generate Context

Generate a complete context including file maps, code maps, and selected file contents.

**Endpoint:** `POST /api/context/generate`

**Request Body:**
```json
{
  "workspace": "/path/to/repository",
  "files": ["src/index.ts", "src/utils.ts"],      // Optional: specific files
  "folders": ["src/components"],                   // Optional: specific folders
  "patterns": ["**/*.ts", "**/*.tsx"],            // Optional: glob patterns
  "excludePatterns": ["**/*.test.ts"],            // Optional: exclusions
  "maxTokens": 100000,                            // Optional: token limit (default: 100000)
  "useGitignore": true,                           // Optional: respect .gitignore (default: true)
  "useAiIgnore": true,                            // Optional: respect .aiignore (default: true)
  "maxFiles": 100                                 // Optional: max files to include
}
```

**Response:**
```json
{
  "fileMap": {
    "structure": [
      {
        "name": "src",
        "path": "src",
        "type": "directory",
        "selected": true,
        "children": [
          {
            "name": "index.ts",
            "path": "src/index.ts",
            "type": "file",
            "language": "TypeScript",
            "size": 1024,
            "selected": true
          }
        ]
      }
    ],
    "totalFiles": 150,
    "selectedFiles": 45,
    "languages": {
      "TypeScript": 30,
      "JavaScript": 10,
      "CSS": 5
    },
    "sizeBytes": 524288
  },
  "codeMap": {
    "functions": [
      {
        "name": "processData",
        "signature": "async function processData(input: DataInput): Promise<DataOutput>",
        "file": "src/processor.ts",
        "line": 15,
        "complexity": 7,
        "exported": true,
        "async": true,
        "importanceScore": 85
      }
    ],
    "classes": [
      {
        "name": "DataService",
        "file": "src/services/data.ts",
        "line": 10,
        "exported": true,
        "methods": ["constructor", "fetch", "process", "save"],
        "properties": ["config", "cache"],
        "importanceScore": 90
      }
    ],
    "interfaces": [],
    "types": [],
    "totalSymbols": 125,
    "languages": {
      "typescript": 100,
      "javascript": 25
    }
  },
  "selectedFiles": [
    {
      "path": "src/index.ts",
      "content": "// File content here...",
      "language": "typescript",
      "tokens": 250
    }
  ],
  "metadata": {
    "workspace": "/path/to/repository",
    "timestamp": 1699123456789,
    "commitSha": "abc123def456",
    "totalTokens": 45000,
    "fileCount": 45,
    "symbolCount": 125,
    "parseTimeMs": 342.5,
    "cacheHits": 120,
    "cacheMisses": 5
  }
}
```

**Status Codes:**
- `200 OK`: Context generated successfully
- `400 Bad Request`: Invalid request parameters
- `500 Internal Server Error`: Generation failed

---

### 2. Get File Map

Get only the file structure map without code analysis.

**Endpoint:** `GET /api/context/file-map`

**Query Parameters:**
- `workspace` (required): Path to the repository

**Example:**
```
GET /api/context/file-map?workspace=/path/to/repo
```

**Response:**
```json
{
  "structure": [...],
  "totalFiles": 150,
  "selectedFiles": 45,
  "languages": {...},
  "sizeBytes": 524288
}
```

---

### 3. Get Code Map

Get symbol summaries without full file contents.

**Endpoint:** `GET /api/context/code-map`

**Query Parameters:**
- `workspace` (required): Path to the repository
- `files` (optional): Comma-separated list of files to analyze

**Example:**
```
GET /api/context/code-map?workspace=/path/to/repo&files=src/index.ts,src/utils.ts
```

**Response:**
```json
{
  "functions": [...],
  "classes": [...],
  "interfaces": [...],
  "types": [...],
  "totalSymbols": 125,
  "languages": {...}
}
```

---

### 4. Invalidate Cache

Clear cached data for a workspace or specific files.

**Endpoint:** `POST /api/context/invalidate`

**Request Body:**
```json
{
  "workspace": "/path/to/repository",
  "files": ["src/modified.ts"]  // Optional: specific files only
}
```

**Response:**
```json
{
  "success": true,
  "message": "Cache invalidated"
}
```

---

### 5. Get Metrics

Retrieve performance metrics and cache statistics.

**Endpoint:** `GET /api/context/metrics`

**Query Parameters:**
- `workspace` (required): Path to the repository

**Response:**
```json
{
  "cacheMetrics": {
    "hits": 1250,
    "misses": 45,
    "hitRate": 96.5,
    "avgResponseTimeMs": 12.3,
    "memoryUsageBytes": 52428800
  },
  "workspace": "/path/to/repository",
  "treeSize": 1500
}
```

## WebSocket Events

When incremental updates are enabled, the following events are emitted:

### file-change
```json
{
  "type": "file-change",
  "data": {
    "type": "change",
    "path": "/path/to/file.ts",
    "timestamp": 1699123456789
  }
}
```

### context-updated
```json
{
  "type": "context-updated",
  "data": {
    "files": ["src/modified.ts"],
    "timestamp": 1699123456789,
    "duration": 45.2
  }
}
```

## Usage Examples

### Basic Context Generation

```bash
curl -X POST http://localhost:3000/api/context/generate \
  -H "Content-Type: application/json" \
  -d '{
    "workspace": "/Users/dev/myproject",
    "patterns": ["src/**/*.ts"],
    "maxTokens": 50000
  }'
```

### TypeScript Client

```typescript
interface ContextOptions {
  workspace: string;
  patterns?: string[];
  maxTokens?: number;
}

async function generateContext(options: ContextOptions) {
  const response = await fetch('http://localhost:3000/api/context/generate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(options)
  });
  
  if (!response.ok) {
    throw new Error(`Context generation failed: ${response.statusText}`);
  }
  
  return await response.json();
}

// Usage
const context = await generateContext({
  workspace: '/path/to/repo',
  patterns: ['src/**/*.ts', '!**/*.test.ts'],
  maxTokens: 100000
});
```

### Python Client

```python
import requests
import json

def generate_context(workspace, patterns=None, max_tokens=100000):
    url = 'http://localhost:3000/api/context/generate'
    payload = {
        'workspace': workspace,
        'patterns': patterns or ['**/*.py'],
        'maxTokens': max_tokens
    }
    
    response = requests.post(url, json=payload)
    response.raise_for_status()
    return response.json()

# Usage
context = generate_context(
    workspace='/path/to/repo',
    patterns=['src/**/*.py', 'lib/**/*.py'],
    max_tokens=50000
)
```

## Performance Characteristics

| Operation | Target | Typical |
|-----------|--------|---------|
| Initial context (1K files) | <5s | 2-3s |
| Initial context (10K files) | <5s | 3-4s |
| Incremental update | <100ms | 30-50ms |
| File map only | <500ms | 100-200ms |
| Code map only | <1s | 300-500ms |
| Cache hit rate | >90% | 92-95% |

## Token Optimization

The API automatically optimizes token usage:

1. **File Map** (10% of budget): Directory structure
2. **Code Map** (30% of budget): Symbol summaries
3. **Content** (60% of budget): Actual file contents

Files are prioritized by:
- Export status (public API surface)
- Recency (recently modified)
- Complexity (cyclomatic complexity)
- References (import frequency)
- Entry points (main/index files)
- Working set (currently open files)

## Error Handling

All errors follow this format:

```json
{
  "error": "Error message",
  "details": {
    "field": "Additional context"
  }
}
```

Common errors:
- `400`: Invalid workspace path
- `400`: Invalid pattern syntax
- `413`: Token limit exceeded
- `500`: Parser failure
- `503`: File system access error

## Rate Limiting

Currently no rate limiting (will be added in Phase 4).

## Versioning

API version: `1.0.0`
Phase: `2`

Future versions will maintain backwards compatibility or provide migration paths.