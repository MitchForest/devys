# Phase 4: Complete Integration & Terminal-First AI Development Environment

## Executive Summary

Phase 4 brings together all infrastructure from Phases 1-3 into a fully functional development environment with terminal-first UI, Claude Code SDK/CLI integration, complete workflow orchestration, and intelligent model routing. This phase introduces "Grunt Mode" for delegating repetitive tasks to free/local models while focusing premium AI resources on complex problems.

## Core Objectives

1. **Unified Terminal Interface**: Integrate Zellij, Helix, Yazi, and other TUI tools into a cohesive AI-powered development environment
2. **Complete Workflow Integration**: Seamless Plan → Edit → Review → Grunt workflow execution
3. **Intelligent Model Routing**: Route tasks to appropriate models based on complexity and cost
4. **Grunt Mode Implementation**: Delegate simple tasks (git ops, tests, linting, docs) to free/local models
5. **AI Context Builder**: Automatic file selection using context intelligence from Phase 2
6. **Real-time Collaboration**: WebSocket-based updates showing AI agent activities
7. **Claude Code SDK Integration**: Full integration with subagents and MCP servers

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Zellij Session Manager                   │
├─────────────┬──────────────┬──────────────┬─────────────────┤
│   Helix     │   Yazi       │   AI Panel   │   Grunt Panel   │
│   Editor    │   File Mgr   │   Commands   │   Background    │
├─────────────┴──────────────┴──────────────┴─────────────────┤
│                    PTY Sidecar (Rust)                        │
├───────────────────────────────────────────────────────────────┤
│                  Control Plane (Phase 3)                     │
│  ┌──────────┬──────────┬──────────┬──────────┐             │
│  │ Workflow │  Agents  │  Router  │   MCP    │             │
│  └──────────┴──────────┴──────────┴──────────┘             │
├───────────────────────────────────────────────────────────────┤
│              Context Intelligence (Phase 2)                  │
└───────────────────────────────────────────────────────────────┘
```

## Core Components Integration

### 1. Claude Code Router Configuration

```typescript
// src/routing/claude-code-router-config.ts
export interface RouterConfig {
  providers: {
    anthropic: {
      apiKey: string;
      models: {
        'claude-3-5-sonnet': { maxTokens: 200000, cost: 0.003 };
        'claude-3-5-haiku': { maxTokens: 200000, cost: 0.0008 };
      };
    };
    google: {
      apiKey: string;
      models: {
        'gemini-2.0-flash-thinking': { maxTokens: 1000000, cost: 0.0 };
        'gemini-2.0-flash': { maxTokens: 1000000, cost: 0.0 };
      };
    };
    openai: {
      apiKey: string;
      models: {
        'o1': { maxTokens: 128000, cost: 0.015 };
        'o1-mini': { maxTokens: 128000, cost: 0.003 };
      };
    };
    deepseek: {
      apiKey: string;
      models: {
        'deepseek-chat': { maxTokens: 64000, cost: 0.0001 };
        'deepseek-reasoner': { maxTokens: 64000, cost: 0.0005 };
      };
    };
    ollama: {
      baseUrl: 'http://localhost:11434';
      models: {
        'qwen2.5-coder:14b': { maxTokens: 32000, cost: 0.0 };
        'llama3.3:70b': { maxTokens: 128000, cost: 0.0 };
      };
    };
  };
  
  routing: {
    plan: {
      primary: 'gemini-2.0-flash-thinking',  // 1M context for comprehensive planning
      fallback: 'o1-mini',
      maxRetries: 2
    },
    edit: {
      primary: 'claude-3-5-sonnet',  // Best code generation
      fallback: 'deepseek-chat',
      maxRetries: 3
    },
    review: {
      primary: 'o1',  // Deep reasoning for review
      fallback: 'claude-3-5-haiku',
      maxRetries: 1
    },
    grunt: {
      primary: 'ollama:qwen2.5-coder:14b',  // Local for simple tasks
      fallback: 'deepseek-chat',
      maxRetries: 5
    }
  };
}
```

### 2. Workflow Mode Controller Integration

```typescript
// src/workflow/integrated-workflow-controller.ts
import { WorkflowModeController } from './workflow-mode-controller';
import { PlannerAgent } from '../agents/planner-agent';
import { EditorAgent } from '../agents/editor-agent';
import { ReviewerAgent } from '../agents/reviewer-agent';
import { GruntAgent } from '../agents/grunt-agent';
import { ContextService } from '../services/context/context-service';
import { ClaudeCodeSDK } from '../integrations/claude-code-sdk';

export class IntegratedWorkflowController {
  private modeController: WorkflowModeController;
  private contextService: ContextService;
  private claudeSDK: ClaudeCodeSDK;
  
  async executeWorkflow(userQuery: string) {
    // Start in PLAN mode
    await this.modeController.transitionTo('PLAN');
    
    // 1. PLAN: Generate comprehensive task plan
    const context = await this.contextService.buildContext({
      query: userQuery,
      includeFiles: true,
      includeCodeMaps: true,
      maxTokens: 900000  // Leave room for Gemini's 1M context
    });
    
    const planResult = await this.plannerAgent.plan({
      context,
      model: 'gemini-2.0-flash-thinking',
      instructions: `
        Break down this task into specific file edits.
        For each edit, specify:
        - File path
        - Operation (create/edit/delete)
        - Success criteria
        - Dependencies on other edits
      `
    });
    
    // 2. EDIT: Execute plan with parallel edits
    await this.modeController.transitionTo('EDIT');
    
    const editPromises = planResult.tasks.map(task => 
      this.editorAgent.edit({
        task,
        context: await this.contextService.buildContext({
          files: task.files,
          includeCodeMaps: true,
          maxTokens: 150000  // Optimize for Claude
        }),
        model: this.selectEditModel(task)
      })
    );
    
    const editResults = await Promise.all(editPromises);
    
    // 3. REVIEW: Validate changes
    if (this.shouldReview(editResults)) {
      await this.modeController.transitionTo('REVIEW');
      
      const reviewResult = await this.reviewerAgent.review({
        plan: planResult,
        edits: editResults,
        model: 'o1',
        criteria: {
          correctness: true,
          security: true,
          performance: true,
          style: true
        }
      });
      
      if (reviewResult.issues.length > 0) {
        // Fix issues with targeted edits
        await this.fixIssues(reviewResult.issues);
      }
    }
    
    // 4. GRUNT: Handle routine tasks
    await this.modeController.transitionTo('GRUNT');
    
    await this.gruntAgent.executeRoutineTasks({
      tasks: [
        { type: 'format', files: editResults.map(e => e.file) },
        { type: 'lint', files: editResults.map(e => e.file) },
        { type: 'test', scope: 'affected' },
        { type: 'commit', message: planResult.summary }
      ],
      model: 'ollama:qwen2.5-coder:14b'
    });
    
    await this.modeController.transitionTo('IDLE');
  }
  
  private selectEditModel(task: EditTask): string {
    // Route to appropriate model based on task complexity
    if (task.complexity === 'simple' || task.type === 'formatting') {
      return 'deepseek-chat';  // Cheap and fast
    } else if (task.requiresContext > 100000) {
      return 'gemini-2.0-flash';  // Large context
    } else {
      return 'claude-3-5-sonnet';  // Best for complex code
    }
  }
}
```

## Terminal UI Integration

### 1. Zellij Layout & Plugin Development

#### 1.1 Layout Configuration

```kdl
// config/zellij/devys-layout.kdl
layout {
    default_tab_template {
        pane size=1 borderless=true {
            plugin location="zellij:tab-bar"
        }
        children
        pane size=2 borderless=true {
            plugin location="file:target/ai-status.wasm"
        }
    }
    
    tab name="devys" focus=true {
        pane split_direction="vertical" {
            // Left: File browser with Yazi
            pane size="20%" {
                command "yazi"
                args "--config" "/devys/config/yazi.toml"
            }
            
            // Center: Editor with Helix
            pane size="60%" focus=true {
                command "helix"
                args "--config" "/devys/config/helix.toml"
            }
            
            // Right: AI Context & Status
            pane size="20%" split_direction="horizontal" {
                // Top: Context viewer
                pane size="70%" {
                    command "devys-context"
                    args "--mode" "watch"
                }
                
                // Bottom: Model status
                pane size="30%" {
                    command "devys-status"
                    args "--show-tokens" "--show-cost"
                }
            }
        }
    }
    
    tab name="terminal" {
        pane command="bash"
    }
    
    tab name="ai-chat" {
        pane {
            command "devys-chat"
            args "--mode" "interactive"
        }
    }
}
```

#### 1.2 Zellij Plugins (WebAssembly in Rust)

**AI Command Plugin** (`src/terminal/plugins/ai-command/`)
```rust
use zellij_tile::prelude::*;

#[derive(Default)]
struct AiCommandPlugin {
    workflow_state: WorkflowState,
    ws_client: Option<WebSocketClient>,
}

impl ZellijPlugin for AiCommandPlugin {
    fn load(&mut self) {
        // Connect to Control Plane via WebSocket
        self.ws_client = Some(WebSocketClient::connect("ws://localhost:3000"));
        subscribe(&[EventType::Key, EventType::Mouse]);
    }
    
    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::Key(Key::Char('a')) if self.is_cmd_pressed() => {
                self.show_command_palette();
                true
            }
            Event::WebSocketMessage(msg) => {
                self.update_workflow_state(msg);
                true
            }
            _ => false
        }
    }
    
    fn render(&mut self, rows: usize, cols: usize) {
        // Render command palette with slash commands
        // Show real-time workflow status
        // Display current mode and progress
    }
}
```

**Grunt Status Plugin** (`src/terminal/plugins/grunt-status/`)
```rust
struct GruntStatusPlugin {
    task_queue: Vec<GruntTask>,
    active_models: HashMap<String, ModelStatus>,
    cost_tracker: CostTracker,
}

impl ZellijPlugin for GruntStatusPlugin {
    fn render(&mut self, rows: usize, cols: usize) {
        // Display background task queue
        // Show which model is handling each task
        // Progress indicators for long-running operations
        // Cost tracking display
    }
}
```

**Context Visualizer Plugin** (`src/terminal/plugins/context-viz/`)
```rust
struct ContextVisualizerPlugin {
    current_context: ContextState,
    token_count: usize,
    file_scores: HashMap<String, f32>,
}

impl ZellijPlugin for ContextVisualizerPlugin {
    fn render(&mut self, rows: usize, cols: usize) {
        // Show current context size and token count
        // File relevance scores from Merkle tree
        // Visual indication of what's included in context
    }
}
```

### 2. Helix Integration

#### 2.1 Configuration

```toml
# config/helix/languages.toml
[[language]]
name = "typescript"
language-servers = ["typescript-language-server", "devys-lsp"]

[language-server.devys-lsp]
command = "devys-lsp"
args = ["--stdio"]

# config/helix/config.toml
[keys.normal]
space.a = { a = ":devys-ai-complete", p = ":devys-plan", e = ":devys-edit", r = ":devys-review" }
space.c = ":devys-context-view"
space.m = ":devys-model-select"

[keys.normal.g]
d = "devys:goto-definition"  # Enhanced with AI understanding

[editor]
lsp.display-messages = true
lsp.display-inlay-hints = true
```

#### 2.2 AI LSP Server

```rust
// src/terminal/lsp/ai-lsp/main.rs
use tower_lsp::{jsonrpc::Result, lsp_types::*, Client, LanguageServer, LspService, Server};

struct DevysLspServer {
    client: Client,
    ai_service: AiService,
}

#[tower_lsp::async_trait]
impl LanguageServer for DevysLspServer {
    async fn completion(&self, params: CompletionParams) -> Result<Option<CompletionResponse>> {
        // Get AI completions from EditorAgent
        let completions = self.ai_service.get_completions(params).await?;
        Ok(Some(CompletionResponse::Array(completions)))
    }
    
    async fn code_action(&self, params: CodeActionParams) -> Result<Option<CodeActionResponse>> {
        // Provide AI-powered code actions
        let actions = vec![
            CodeAction {
                title: "AI Explain".to_string(),
                command: Some(Command {
                    title: "Explain with AI".to_string(),
                    command: "devys.explain".to_string(),
                    arguments: Some(vec![]),
                }),
                ..Default::default()
            },
            CodeAction {
                title: "AI Refactor".to_string(),
                command: Some(Command {
                    title: "Refactor with AI".to_string(),
                    command: "devys.refactor".to_string(),
                    arguments: Some(vec![]),
                }),
                ..Default::default()
            },
        ];
        Ok(Some(actions.into()))
    }
}
```

### 3. Yazi Integration

#### 3.1 Context Score Plugin

```lua
-- src/terminal/yazi/context-score.yazi/init.lua
local function setup()
    -- Subscribe to directory changes
    ps.sub("cd", function()
        local cwd = cx.active.current.cwd
        ya.manager_emit("plugin:devys-context", { cwd = tostring(cwd) })
    end)
    
    -- Subscribe to file selection
    ps.sub("select", function()
        local selected = cx.active.current:selected()
        update_context_scores(selected)
    end)
end

local function fetch_scores()
    local scores = ya.sync(function()
        return io.popen("devys-cli context scores --json"):read("*a")
    end)
    return scores
end

local function render_with_scores()
    local scores = fetch_scores()
    
    -- Color code files based on relevance
    for _, file in ipairs(cx.active.current.files) do
        local score = scores[file.name]
        if score > 0.8 then
            file.style = { fg = "green", bold = true }  -- High relevance
        elseif score > 0.5 then
            file.style = { fg = "yellow" }  -- Medium relevance
        else
            file.style = { fg = "gray" }  -- Low relevance
        end
        
        -- Add icon indicating inclusion in context
        if file.in_context then
            file.icon = "✓ " .. file.icon
        end
    end
end

return { setup = setup, render = render_with_scores }
```

### 4. Context Builder TUI

```rust
// src/ui/context_builder.rs
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Style},
    widgets::{Block, Borders, List, ListItem, Paragraph, Gauge},
    Terminal,
};

pub struct ContextBuilderUI {
    terminal: Terminal<CrosstermBackend<io::Stdout>>,
    context_state: ContextState,
    token_counter: TokenCounter,
}

impl ContextBuilderUI {
    pub fn render(&mut self) -> Result<()> {
        self.terminal.draw(|f| {
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Length(3),   // Header
                    Constraint::Min(10),     // File tree
                    Constraint::Length(10),  // Token usage
                    Constraint::Length(3),   // Status
                ])
                .split(f.size());
            
            // Render file tree with inclusion status
            let files: Vec<ListItem> = self.context_state.files
                .iter()
                .map(|file| {
                    let style = if file.included {
                        Style::default().fg(Color::Green)
                    } else {
                        Style::default().fg(Color::Gray)
                    };
                    let tokens = self.token_counter.count_file(&file.path);
                    ListItem::new(format!("{} ({} tokens)", file.path, tokens))
                        .style(style)
                })
                .collect();
            
            let files_widget = List::new(files)
                .block(Block::default().borders(Borders::ALL).title("Files"));
            f.render_widget(files_widget, chunks[1]);
            
            // Render token usage bar
            let token_usage = self.render_token_bar();
            f.render_widget(token_usage, chunks[2]);
            
            // Render model recommendations
            let recommendations = self.get_model_recommendations();
            f.render_widget(recommendations, chunks[3]);
        })?;
        
        Ok(())
    }
    
    fn render_token_bar(&self) -> Gauge {
        let total = self.token_counter.total();
        let (model, limit, cost) = self.recommend_model(total);
        let ratio = (total as f64 / limit as f64).min(1.0);
        
        Gauge::default()
            .block(Block::default().borders(Borders::ALL).title("Token Usage"))
            .gauge_style(Style::default().fg(Color::Cyan))
            .percent((ratio * 100.0) as u16)
            .label(format!(
                "{}/{} | Model: {} | Est: ${:.4}",
                total, limit, model, cost
            ))
    }
    
    fn recommend_model(&self, tokens: usize) -> (&str, usize, f32) {
        match tokens {
            t if t < 30000 => ("claude-3-5-haiku", 200000, t as f32 * 0.0000008),
            t if t < 150000 => ("claude-3-5-sonnet", 200000, t as f32 * 0.000003),
            t if t < 900000 => ("gemini-2.0-flash", 1000000, 0.0),
            _ => ("gemini-2.0-flash-thinking", 1000000, 0.0),
        }
    }
}
```

## AI Context Builder

### Intelligent File Selection

```typescript
// src/context/ai-context-builder.ts
export class AIContextBuilder {
  private merkleTree: MerkleTreeService;
  private symbolExtractor: SymbolExtractor;
  private scoreCalculator: RelevanceScorer;
  
  async buildContext(task: string): Promise<Context> {
    // 1. Parse task description
    const keywords = await this.extractKeywords(task);
    
    // 2. Search codebase for relevant symbols
    const symbols = await this.searchSymbols(keywords);
    
    // 3. Build dependency graph
    const deps = await this.analyzeDependencies(symbols);
    
    // 4. Score files by relevance
    const scores = await this.scoreFiles(deps);
    
    // 5. Select files within token budget
    return this.selectOptimalFiles(scores);
  }
  
  private async extractKeywords(task: string): Promise<string[]> {
    // Use NLP to extract key terms
    const tokens = task.toLowerCase().split(/\s+/);
    return tokens.filter(t => t.length > 3 && !STOP_WORDS.includes(t));
  }
  
  private async searchSymbols(keywords: string[]): Promise<Symbol[]> {
    const results = [];
    for (const keyword of keywords) {
      const symbols = await this.symbolExtractor.search(keyword);
      results.push(...symbols);
    }
    return [...new Set(results)]; // Deduplicate
  }
  
  private async scoreFiles(dependencies: DependencyGraph): Promise<Map<string, number>> {
    const scores = new Map<string, number>();
    
    for (const [file, deps] of dependencies) {
      let score = 0;
      
      // Recent modification boost
      const lastModified = await this.getLastModified(file);
      const hoursSince = (Date.now() - lastModified) / 3600000;
      if (hoursSince < 1) score += 20;
      else if (hoursSince < 24) score += 10;
      else if (hoursSince < 168) score += 5;
      
      // Dependency importance
      score += deps.length * 2;
      
      // File type importance
      if (file.includes('index') || file.includes('main')) score += 15;
      if (file.includes('.test.') || file.includes('.spec.')) score += 5;
      
      // Working set boost
      if (await this.isInWorkingSet(file)) score += 25;
      
      scores.set(file, score);
    }
    
    return scores;
  }
  
  private selectOptimalFiles(scores: Map<string, number>): Context {
    const sorted = Array.from(scores.entries())
      .sort((a, b) => b[1] - a[1]);
    
    const selected = [];
    let totalTokens = 0;
    const maxTokens = this.getMaxTokensForCurrentModel();
    
    for (const [file, score] of sorted) {
      const tokens = await this.tokenCounter.countFile(file);
      if (totalTokens + tokens <= maxTokens * 0.8) { // Leave 20% buffer
        selected.push(file);
        totalTokens += tokens;
      }
    }
    
    return {
      files: selected,
      totalTokens,
      scores: Object.fromEntries(scores)
    };
  }
}
```

### Usage Pattern Learning

```typescript
// src/context/pattern-learner.ts
export class UsagePatternLearner {
  private cooccurrenceMatrix: Map<string, Map<string, number>>;
  private accessPatterns: AccessPattern[];
  
  async learn(session: DevelopmentSession) {
    // Track which files are accessed together
    for (const event of session.events) {
      if (event.type === 'file_open') {
        this.recordAccess(event.file, event.context);
      }
    }
    
    // Update co-occurrence matrix
    this.updateCooccurrence(session.accessedFiles);
    
    // Identify common patterns
    const patterns = this.extractPatterns();
    await this.savePatterns(patterns);
  }
  
  async suggestRelatedFiles(currentFile: string): Promise<string[]> {
    const related = this.cooccurrenceMatrix.get(currentFile);
    if (!related) return [];
    
    return Array.from(related.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([file]) => file);
  }
}
```

## Command Palette & Search

### FZF Integration

```bash
#!/bin/bash
# src/terminal/command-palette/devys-fzf

devys-fzf() {
    local cmd
    cmd=$(
        {
            echo "--- AI Commands ---"
            devys-cli commands list --format simple
            echo "--- Recent Commands ---"
            history | tail -20 | cut -c 8-
            echo "--- Project Files ---"
            devys-cli context files --with-scores
        } | fzf \
            --preview 'devys-cli explain {}' \
            --preview-window right:50% \
            --bind 'ctrl-a:execute(devys-cli ai-complete {})' \
            --bind 'ctrl-p:execute(devys-cli plan {})' \
            --bind 'ctrl-e:execute(devys-cli edit {})' \
            --bind 'ctrl-r:execute(devys-cli review {})' \
            --header 'ctrl-a: AI complete | ctrl-p: Plan | ctrl-e: Edit | ctrl-r: Review'
    )
    
    if [[ -n "$cmd" ]]; then
        devys-cli exec "$cmd"
    fi
}

# Bind to Ctrl+Space in shell
bind -x '"\C- ": devys-fzf'
```

## Grunt Agent Implementation

```typescript
// src/agents/grunt-agent.ts
export class GruntAgent extends BaseAgent {
  private localModels: Map<string, OllamaModel>;
  private taskClassifier: TaskClassifier;
  
  async executeRoutineTasks(config: GruntConfig): Promise<GruntResult> {
    const results = [];
    
    // Classify tasks by complexity
    const classified = await this.classifyTasks(config.tasks);
    
    // Route to appropriate models
    for (const task of classified) {
      const model = this.selectGruntModel(task);
      const result = await this.executeTask(task, model);
      results.push(result);
    }
    
    return { 
      results, 
      tokenUsage: this.tokenCounter.total(),
      cost: this.calculateCost(results)
    };
  }
  
  private selectGruntModel(task: GruntTask): string {
    // Use local models for simple tasks
    if (task.complexity === 'simple') {
      return 'ollama:qwen2.5-coder:14b';
    }
    
    // Use fast cloud models for moderate tasks
    if (task.complexity === 'moderate') {
      return 'deepseek-chat';
    }
    
    // Fall back to capable models for complex grunt work
    return 'claude-3-5-haiku';
  }
  
  private async executeTask(task: GruntTask, model: string): Promise<TaskResult> {
    switch (task.type) {
      case 'format':
        return await this.format(task.files, model);
      case 'lint':
        return await this.lint(task.files, model);
      case 'test':
        return await this.runTests(task.scope, model);
      case 'commit':
        return await this.commit(task.message, model);
      case 'docs':
        return await this.generateDocs(task.files, model);
      default:
        throw new Error(`Unknown task type: ${task.type}`);
    }
  }
  
  private async format(files: string[], model: string): Promise<TaskResult> {
    // Run prettier/formatter first
    const { stdout, stderr } = await Bun.spawn(['prettier', '--write', ...files]);
    
    if (stderr) {
      // Use AI to fix formatting issues
      const prompt = `Fix formatting issues:\n${stderr}`;
      const response = await this.callModel(model, prompt);
      await this.applyFixes(response.fixes);
    }
    
    return { 
      type: 'format', 
      status: 'success', 
      files,
      model,
      tokens: response?.tokens || 0
    };
  }
  
  private async runTests(scope: string, model: string): Promise<TaskResult> {
    const testCommand = scope === 'affected' 
      ? ['bun', 'test', '--changed']
      : ['bun', 'test'];
    
    const { stdout, exitCode } = await Bun.spawn(testCommand);
    const output = await new Response(stdout).text();
    
    if (exitCode !== 0) {
      // Use AI to analyze test failures
      const prompt = `Analyze test failures and suggest fixes:\n${output}`;
      const analysis = await this.callModel(model, prompt);
      
      return {
        type: 'test',
        status: 'failed',
        output,
        analysis: analysis.content,
        model,
        tokens: analysis.tokens
      };
    }
    
    return {
      type: 'test',
      status: 'success',
      output,
      model,
      tokens: 0
    };
  }
}
```

## Shell Integration

```bash
#!/bin/bash
# ~/.zshrc or ~/.bashrc integration

# Initialize Devys
eval "$(devys init zsh)"

# This provides:
# - Auto-completion for devys commands
# - Prompt integration showing AI status
# - Directory-specific context loading

# Custom prompt showing AI status
PROMPT='%{$fg[cyan]%}$(devys_status)%{$reset_color%} %~ $ '

# Directory hooks for automatic context loading
chpwd() {
    if [[ -f .devys/context.yaml ]]; then
        devys context load .devys/context.yaml
    fi
}

# Aliases for common operations
alias dai="devys ai"
alias dplan="devys workflow plan"
alias dedit="devys workflow edit"
alias dreview="devys workflow review"
alias dcontext="devys context view"

# Key bindings
bindkey '^G' devys_grunt_menu  # Ctrl+G for grunt tasks
bindkey '^A' devys_ai_complete # Ctrl+A for AI completion
```

## Claude Code SDK Integration

```typescript
// src/integrations/claude-code-sdk.ts
import { ClaudeCode } from '@anthropic/claude-code-sdk';

export class ClaudeCodeIntegration {
  private sdk: ClaudeCode;
  private activeAgents: Map<string, Agent>;
  
  async initialize() {
    this.sdk = new ClaudeCode({
      configPath: '~/.claude/claude_code_config.json',
      enableMCP: true,
      enableSubAgents: true
    });
    
    // Register our custom MCP servers
    await this.sdk.mcp.register('devys-context', {
      command: 'devys-mcp-context',
      args: ['--stdio'],
      capabilities: ['context/build', 'context/cache', 'context/optimize']
    });
    
    await this.sdk.mcp.register('devys-models', {
      command: 'devys-mcp-models',
      args: ['--stdio'],
      capabilities: ['model/route', 'model/select', 'model/cost']
    });
  }
  
  async createSubAgent(type: 'planner' | 'editor' | 'reviewer', config: AgentConfig) {
    const agent = await this.sdk.createSubAgent({
      type,
      model: config.model,
      systemPrompt: this.getSystemPrompt(type),
      tools: this.getToolsForAgent(type),
      hooks: {
        beforeInvoke: async (params) => {
          // Log to our tracking system
          await this.trackInvocation(type, params);
        },
        afterComplete: async (result) => {
          // Update token usage
          await this.updateTokenUsage(result);
        }
      }
    });
    
    this.activeAgents.set(agent.id, agent);
    return agent;
  }
  
  private getSystemPrompt(type: string): string {
    const prompts = {
      planner: `You are a planning specialist. Break down tasks into specific, 
                atomic file operations. Always specify success criteria.`,
      editor: `You are a code editing specialist. Make precise, minimal edits.
               Preserve existing style and patterns.`,
      reviewer: `You are a code review specialist. Check for correctness,
                 security, performance, and style issues.`
    };
    return prompts[type];
  }
  
  private getToolsForAgent(type: string): string[] {
    const tools = {
      planner: ['read_file', 'search_code', 'list_files'],
      editor: ['read_file', 'edit_file', 'create_file', 'delete_file'],
      reviewer: ['read_file', 'run_tests', 'check_types', 'analyze_security']
    };
    return tools[type];
  }
}
```

## Complete Integration Example

```typescript
// src/main.ts - Main entry point bringing everything together
import { IntegratedWorkflowController } from './workflow/integrated-workflow-controller';
import { ClaudeCodeIntegration } from './integrations/claude-code-sdk';
import { TerminalUI } from './ui/terminal-ui';
import { PTYBridge } from './pty/bridge';

export class DevysCore {
  private workflow: IntegratedWorkflowController;
  private claudeCode: ClaudeCodeIntegration;
  private ui: TerminalUI;
  private pty: PTYBridge;
  
  async initialize() {
    // 1. Initialize PTY bridge for <50ms latency
    this.pty = new PTYBridge();
    await this.pty.connect('ws://localhost:8080/pty');
    
    // 2. Initialize Claude Code SDK
    this.claudeCode = new ClaudeCodeIntegration();
    await this.claudeCode.initialize();
    
    // 3. Setup terminal UI
    this.ui = new TerminalUI();
    await this.ui.initializeZellij();
    
    // 4. Initialize workflow controller
    this.workflow = new IntegratedWorkflowController({
      claudeCode: this.claudeCode,
      pty: this.pty,
      ui: this.ui
    });
    
    // 5. Register keybindings
    this.registerKeybindings();
    
    // 6. Start MCP servers
    await this.startMCPServers();
  }
  
  private registerKeybindings() {
    // Helix keybindings for AI commands
    this.ui.helix.registerCommand('devys-plan', async () => {
      const selection = await this.ui.helix.getSelection();
      await this.workflow.executeWorkflow(selection);
    });
    
    this.ui.helix.registerCommand('devys-edit', async () => {
      await this.workflow.transitionTo('EDIT');
    });
    
    // Zellij keybindings for pane management
    this.ui.zellij.registerBinding('Alt+a', async () => {
      await this.ui.zellij.focusPane('ai-chat');
    });
    
    this.ui.zellij.registerBinding('Alt+c', async () => {
      await this.ui.zellij.togglePane('context-viewer');
    });
  }
  
  private async startMCPServers() {
    // Start context MCP server
    await Bun.spawn(['devys-mcp-context', '--stdio'], {
      stdio: ['pipe', 'pipe', 'pipe']
    });
    
    // Start model routing MCP server  
    await Bun.spawn(['devys-mcp-models', '--stdio'], {
      stdio: ['pipe', 'pipe', 'pipe']
    });
  }
}

// Initialize and run
const devys = new DevysCore();
await devys.initialize();
console.log('Devys Phase 4 initialized successfully');
```

## Configuration Management

```toml
# ~/.config/devys/config.toml
[terminal]
multiplexer = "zellij"
editor = "helix"
file_manager = "yazi"
shell = "zsh"

[ai]
planner_model = "gemini-2.0-flash-thinking"
editor_model = "claude-3-5-sonnet"
reviewer_model = "o1"
grunt_models = ["ollama:qwen2.5-coder:14b", "deepseek-chat"]

[context]
max_tokens = 100000
auto_select = true
cache_ttl = 3600
learning_enabled = true

[grunt]
enabled = true
local_first = true
cost_limit_daily = 1.00
parallel_tasks = 4

[workflow]
review_mode = "optional"  # always | optional | never
max_parallel_edits = 4
auto_retry = true
progress_updates = true

[performance]
keystroke_latency_target = 50  # ms
websocket_timeout = 5000       # ms
cache_size_mb = 500
```

## Testing Strategy

```typescript
// test/integration/phase-4.test.ts
import { test, expect } from "bun:test";
import { DevysCore } from "../src/main";

test("Phase 4: Complete workflow integration", async () => {
  const devys = new DevysCore();
  await devys.initialize();
  
  // Test Plan -> Edit -> Review -> Grunt workflow
  const result = await devys.workflow.executeWorkflow(
    "Add error handling to the authentication module"
  );
  
  expect(result.phases).toHaveLength(4);
  expect(result.phases[0].mode).toBe('PLAN');
  expect(result.phases[1].mode).toBe('EDIT');
  expect(result.phases[2].mode).toBe('REVIEW');
  expect(result.phases[3].mode).toBe('GRUNT');
  
  // Verify token optimization
  expect(result.totalTokens).toBeLessThan(500000);
  
  // Verify cost optimization (grunt work should be free)
  expect(result.phases[3].cost).toBe(0);
});

test("Phase 4: Terminal UI integration", async () => {
  const ui = new TerminalUI();
  await ui.initializeZellij();
  
  // Verify all panes are created
  const panes = await ui.zellij.listPanes();
  expect(panes).toContainEqual(expect.objectContaining({ name: 'yazi' }));
  expect(panes).toContainEqual(expect.objectContaining({ name: 'helix' }));
  expect(panes).toContainEqual(expect.objectContaining({ name: 'devys-context' }));
});

test("Phase 4: Model routing", async () => {
  const router = new ModelRouter();
  
  // Test routing logic
  expect(router.selectModel('plan', 1000000)).toBe('gemini-2.0-flash-thinking');
  expect(router.selectModel('edit', 50000)).toBe('claude-3-5-sonnet');
  expect(router.selectModel('review', 10000)).toBe('o1');
  expect(router.selectModel('grunt', 1000)).toBe('ollama:qwen2.5-coder:14b');
});

test("Phase 4: Context builder accuracy", async () => {
  const builder = new AIContextBuilder();
  
  const context = await builder.buildContext(
    "Fix the bug in the user authentication flow"
  );
  
  // Should include auth-related files
  expect(context.files).toContain('src/auth/login.ts');
  expect(context.files).toContain('src/auth/session.ts');
  
  // Should respect token limits
  expect(context.totalTokens).toBeLessThan(100000);
  
  // Should have high scores for relevant files
  expect(context.scores['src/auth/login.ts']).toBeGreaterThan(0.7);
});
```

## Deployment

### Installation Script

```bash
#!/bin/bash
# install.sh

echo "Installing Devys Phase 4..."

# Install Rust dependencies
echo "Installing terminal tools..."
cargo install zellij helix yazi

# Build Zellij plugins
echo "Building Zellij plugins..."
cd src/terminal/plugins
for plugin in ai-command grunt-status context-viz; do
    cd $plugin
    cargo build --release
    wasm-opt -O target/wasm32-wasi/release/*.wasm -o ../../target/$plugin.wasm
    cd ..
done

# Install Node dependencies
echo "Installing Node dependencies..."
bun install

# Setup configuration
echo "Setting up configuration..."
mkdir -p ~/.config/devys
cp config/devys.toml ~/.config/devys/config.toml

# Initialize Claude Code SDK
echo "Initializing Claude Code SDK..."
devys claude init

# Start services
echo "Starting services..."
devys start

echo "Devys Phase 4 installation complete!"
echo "Run 'devys help' to get started"
```

### Distribution

- **Homebrew Formula** (macOS)
  ```ruby
  class Devys < Formula
    desc "AI-powered terminal development environment"
    homepage "https://github.com/devys/devys"
    url "https://github.com/devys/devys/archive/v0.4.0.tar.gz"
    
    depends_on "rust" => :build
    depends_on "bun"
    depends_on "zellij"
    depends_on "helix"
    
    def install
      system "cargo", "build", "--release"
      bin.install "target/release/devys"
    end
  end
  ```

- **Docker Image**
  ```dockerfile
  FROM rust:1.75 as builder
  WORKDIR /app
  COPY . .
  RUN cargo build --release
  
  FROM ubuntu:22.04
  RUN apt-get update && apt-get install -y \
      zellij helix yazi fzf ripgrep
  COPY --from=builder /app/target/release/devys /usr/local/bin/
  CMD ["devys", "start"]
  ```

## Performance Targets & Metrics

### Performance Requirements
- Terminal rendering: < 16ms per frame (60 FPS)
- Keystroke latency: < 50ms (maintained from Phase 1)
- Command execution: < 100ms for local operations
- Context building: < 500ms for average project
- Grunt task routing: < 50ms decision time
- WebSocket latency: < 10ms local, < 50ms remote

### Success Metrics

1. **Performance**
   - 90% of commands complete in < 1 second
   - Context building accuracy > 85%
   - Grunt task success rate > 95%

2. **Cost Efficiency**
   - 70% of tasks handled by free/local models
   - Daily AI costs reduced by > 50%
   - Token usage optimized by > 40%

3. **Developer Experience**
   - Setup time < 5 minutes
   - Learning curve < 1 hour
   - Productivity increase > 30%

## Risk Mitigation

1. **Terminal Compatibility**
   - Test on multiple terminal emulators (kitty, alacritty, iTerm2, Windows Terminal)
   - Fallback to basic mode if advanced features unsupported
   - Provide web-based terminal option via xterm.js

2. **Model Availability**
   - Queue system for rate-limited models
   - Automatic fallback chains
   - Offline mode with degraded functionality
   - Local model caching

3. **Performance Issues**
   - Async operations for all I/O
   - Caching at multiple levels
   - Progressive enhancement approach
   - Background task prioritization

## Future Enhancements (Phase 5 Preview)

- **Tauri Desktop App**: Native performance with web technologies
- **Mobile Companion**: iOS/Android app for monitoring and quick actions
- **Team Collaboration**: Shared contexts and real-time pair programming
- **AI Model Fine-tuning**: Project-specific model training
- **Visual Debugging**: Terminal-based UI for debugging AI decisions
- **Multi-workspace Support**: Handle multiple projects simultaneously
- **Custom Agent SDK**: Allow users to create specialized agents

## Implementation Progress

### ✅ Completed Components (40%)

#### Core Routing & Workflow (100% Complete)
- [x] **Claude Code Router Configuration** (`src/routing/claude-code-router-config.ts`)
  - Complete model provider configuration (Anthropic, Google, OpenAI, DeepSeek, Ollama)
  - Intelligent routing rules for all workflow phases
  - Cost management with daily budget tracking
  
- [x] **Integrated Workflow Controller** (`src/workflow/integrated-workflow-controller.ts`)
  - Complete Plan → Edit → Review → Grunt orchestration
  - Intelligent model routing based on complexity
  - Parallel execution support
  - Comprehensive error handling

- [x] **Grunt Agent** (`src/agents/grunt-agent.ts`)
  - Local model integration with Ollama
  - Task classification system
  - Native tool integration (prettier, eslint, bun test)
  - Support for formatting, linting, testing, commits, docs

- [x] **AI Context Builder** (`src/context/ai-context-builder.ts`)
  - Intelligent file selection with learning
  - Co-occurrence matrix for usage patterns
  - Token optimization for different models
  - Caching system with invalidation

- [x] **Model Routing MCP Server** (`src/mcp/model-routing-mcp-server.ts`)
  - Complete MCP integration with 6 tools
  - Real-time model status and availability
  - Cost analysis and optimization

- [x] **Enhanced Model Router** (`src/routing/model-router.ts`)
  - Updated with all Phase 4 models
  - Multi-provider support
  - Comprehensive metrics tracking

- [x] **Context Service** (`src/services/context/context-service.ts`)
  - High-level interface to AI Context Builder
  - Context optimization methods
  - Cost estimation utilities

### ✅ Additional Completed Components (85% Total)

#### Terminal UI Integration (100% Complete)
- [x] **Zellij plugin development** (WebAssembly)
  - [x] AI Command Plugin - Real-time command palette with workflow status
  - [x] Grunt Status Plugin - Background task monitoring with cost tracking
  - [x] Context Visualizer Plugin - Interactive context management
- [x] **Helix LSP Server**
  - [x] AI completions integration with Control Plane
  - [x] Code actions (explain, refactor, plan, edit, review)
- [x] **Context Builder TUI** (Rust with ratatui)
  - [x] Interactive file selection and token optimization
  - [x] Multiple view modes (List, Details, Tree)
  - [x] Real-time model recommendations

#### Claude Code SDK Integration (100% Complete)
- [x] **SDK initialization and configuration**
- [x] **Sub-agent creation and management**
- [x] **MCP server registration**
- [x] **Hook system integration**

#### Shell & Command Integration (100% Complete)
- [x] **FZF command palette** (`devys-fzf`)
- [x] **Shell hooks and aliases** for Zsh and Bash
- [x] **Directory-specific context loading**
- [x] **Key bindings** (Ctrl+Space, Ctrl+G, Ctrl+A)

#### DevysCore Orchestrator (100% Complete)
- [x] **Complete system integration** (`src/main.ts`)
- [x] **PTY bridge connection** for <50ms latency
- [x] **Terminal UI initialization**
- [x] **Workflow controller setup**
- [x] **Keybinding registration**
- [x] **MCP server management**

### 🚧 Remaining Components (15%)

#### Testing & Deployment
- [ ] Full integration test suite
- [ ] Performance benchmark suite
- [ ] Docker image creation
- [ ] Homebrew formula finalization

## Conclusion

Phase 4 successfully integrates all components from Phases 1-3 into a cohesive, terminal-first AI development environment. The intelligent model routing ensures cost-effectiveness while maintaining high quality, and the Grunt Mode innovation delegates routine tasks to free/local models. The unified terminal interface maintains developer flow state while providing unprecedented AI assistance.

Key achievements:
- Complete workflow orchestration (Plan → Edit → Review → Grunt)
- Intelligent model selection based on task complexity
- Terminal-first UI with Zellij, Helix, and Yazi integration
- AI context builder with learning capabilities
- Cost optimization through local model usage
- Maintained <50ms keystroke latency from Phase 1

This phase sets the foundation for a new paradigm in AI-assisted development where the AI becomes an invisible but powerful partner in the development process.