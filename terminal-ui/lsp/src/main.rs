use tower_lsp::jsonrpc::Result;
use tower_lsp::lsp_types::*;
use tower_lsp::{Client, LanguageServer, LspService, Server};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::sync::RwLock;

#[derive(Debug)]
struct DevysLspServer {
    client: Client,
    ai_service: AiService,
    document_cache: RwLock<HashMap<Url, String>>,
    context_cache: RwLock<ContextCache>,
}

#[derive(Debug, Default)]
struct ContextCache {
    current_context: Vec<String>,
    token_count: usize,
    last_update: std::time::Instant,
}

#[derive(Debug)]
struct AiService {
    control_plane_url: String,
    client: reqwest::Client,
}

#[derive(Debug, Serialize, Deserialize)]
struct CompletionRequest {
    text: String,
    position: Position,
    context: Vec<String>,
    language: String,
    model: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct CompletionResponse {
    completions: Vec<CompletionItem>,
    model_used: String,
    tokens_used: usize,
    cost: f32,
}

#[derive(Debug, Serialize, Deserialize)]
struct CodeAction {
    title: String,
    kind: String,
    command: String,
    args: Vec<serde_json::Value>,
}

impl AiService {
    fn new() -> Self {
        Self {
            control_plane_url: "http://localhost:3000".to_string(),
            client: reqwest::Client::new(),
        }
    }

    async fn get_completions(&self, request: CompletionRequest) -> anyhow::Result<CompletionResponse> {
        let response = self
            .client
            .post(&format!("{}/api/ai/completions", self.control_plane_url))
            .json(&request)
            .send()
            .await?;

        if !response.status().is_success() {
            return Err(anyhow::anyhow!("AI service returned error: {}", response.status()));
        }

        let completion_response: CompletionResponse = response.json().await?;
        Ok(completion_response)
    }

    async fn get_code_actions(&self, uri: &Url, range: Range, context: Vec<String>) -> anyhow::Result<Vec<CodeAction>> {
        let request = serde_json::json!({
            "uri": uri.to_string(),
            "range": range,
            "context": context,
        });

        let response = self
            .client
            .post(&format!("{}/api/ai/code-actions", self.control_plane_url))
            .json(&request)
            .send()
            .await?;

        if !response.status().is_success() {
            return Err(anyhow::anyhow!("AI service returned error: {}", response.status()));
        }

        let actions: Vec<CodeAction> = response.json().await?;
        Ok(actions)
    }

    async fn explain_code(&self, code: &str, language: &str) -> anyhow::Result<String> {
        let request = serde_json::json!({
            "code": code,
            "language": language,
            "task": "explain"
        });

        let response = self
            .client
            .post(&format!("{}/api/ai/explain", self.control_plane_url))
            .json(&request)
            .send()
            .await?;

        if !response.status().is_success() {
            return Err(anyhow::anyhow!("AI service returned error: {}", response.status()));
        }

        let explanation: serde_json::Value = response.json().await?;
        Ok(explanation["explanation"].as_str().unwrap_or("No explanation available").to_string())
    }

    async fn refactor_code(&self, code: &str, language: &str, instruction: &str) -> anyhow::Result<String> {
        let request = serde_json::json!({
            "code": code,
            "language": language,
            "instruction": instruction,
            "task": "refactor"
        });

        let response = self
            .client
            .post(&format!("{}/api/ai/refactor", self.control_plane_url))
            .json(&request)
            .send()
            .await?;

        if !response.status().is_success() {
            return Err(anyhow::anyhow!("AI service returned error: {}", response.status()));
        }

        let refactored: serde_json::Value = response.json().await?;
        Ok(refactored["refactored_code"].as_str().unwrap_or(code).to_string())
    }
}

#[tower_lsp::async_trait]
impl LanguageServer for DevysLspServer {
    async fn initialize(&self, params: InitializeParams) -> Result<InitializeResult> {
        tracing::info!("Devys LSP Server initializing...");
        
        Ok(InitializeResult {
            capabilities: ServerCapabilities {
                text_document_sync: Some(TextDocumentSyncCapability::Kind(
                    TextDocumentSyncKind::INCREMENTAL,
                )),
                completion_provider: Some(CompletionOptions {
                    resolve_provider: Some(true),
                    trigger_characters: Some(vec![".".to_string(), ":".to_string(), ">".to_string()]),
                    work_done_progress_options: WorkDoneProgressOptions::default(),
                    all_commit_characters: None,
                    completion_item: None,
                }),
                code_action_provider: Some(CodeActionProviderCapability::Simple(true)),
                hover_provider: Some(HoverProviderCapability::Simple(true)),
                definition_provider: Some(OneOf::Left(true)),
                document_symbol_provider: Some(OneOf::Left(true)),
                workspace_symbol_provider: Some(OneOf::Left(true)),
                execute_command_provider: Some(ExecuteCommandOptions {
                    commands: vec![
                        "devys.explain".to_string(),
                        "devys.refactor".to_string(),
                        "devys.optimize".to_string(),
                        "devys.generate-docs".to_string(),
                        "devys.fix-errors".to_string(),
                    ],
                    work_done_progress_options: WorkDoneProgressOptions::default(),
                }),
                ..ServerCapabilities::default()
            },
            server_info: Some(ServerInfo {
                name: "Devys LSP Server".to_string(),
                version: Some("0.1.0".to_string()),
            }),
        })
    }

    async fn initialized(&self, _: InitializedParams) {
        tracing::info!("Devys LSP Server initialized successfully");
        
        self.client
            .log_message(MessageType::INFO, "Devys AI LSP Server ready!")
            .await;
    }

    async fn shutdown(&self) -> Result<()> {
        tracing::info!("Devys LSP Server shutting down");
        Ok(())
    }

    async fn did_open(&self, params: DidOpenTextDocumentParams) {
        tracing::debug!("Document opened: {}", params.text_document.uri);
        
        let mut cache = self.document_cache.write().await;
        cache.insert(params.text_document.uri, params.text_document.text);
    }

    async fn did_change(&self, params: DidChangeTextDocumentParams) {
        tracing::debug!("Document changed: {}", params.text_document.uri);
        
        let mut cache = self.document_cache.write().await;
        if let Some(text) = cache.get_mut(&params.text_document.uri) {
            for change in params.content_changes {
                if let Some(range) = change.range {
                    // Apply incremental change
                    *text = apply_text_change(text, &change.text, range);
                } else {
                    // Full document change
                    *text = change.text;
                }
            }
        }
    }

    async fn completion(&self, params: CompletionParams) -> Result<Option<CompletionResponse>> {
        let uri = &params.text_document_position.text_document.uri;
        let position = params.text_document_position.position;

        tracing::debug!("Completion requested at {}:{}", position.line, position.character);

        // Get document text
        let cache = self.document_cache.read().await;
        let text = match cache.get(uri) {
            Some(text) => text.clone(),
            None => {
                tracing::warn!("Document not found in cache: {}", uri);
                return Ok(None);
            }
        };

        // Determine language from file extension
        let language = get_language_from_uri(uri);

        // Get current context
        let context_cache = self.context_cache.read().await;
        let context = context_cache.current_context.clone();

        // Make AI completion request
        let completion_request = CompletionRequest {
            text,
            position,
            context,
            language,
            model: None, // Let the router decide
        };

        match self.ai_service.get_completions(completion_request).await {
            Ok(ai_response) => {
                let completions: Vec<tower_lsp::lsp_types::CompletionItem> = ai_response
                    .completions
                    .into_iter()
                    .enumerate()
                    .map(|(i, item)| tower_lsp::lsp_types::CompletionItem {
                        label: item.label,
                        kind: Some(CompletionItemKind::TEXT),
                        detail: Some(format!("AI suggestion ({})", ai_response.model_used)),
                        documentation: item.documentation.map(|d| Documentation::String(d)),
                        sort_text: Some(format!("{:02}", i)), // Maintain AI ordering
                        filter_text: Some(item.filter_text.unwrap_or_else(|| item.label.clone())),
                        insert_text: Some(item.insert_text.unwrap_or_else(|| item.label.clone())),
                        insert_text_format: Some(InsertTextFormat::PLAIN_TEXT),
                        ..Default::default()
                    })
                    .collect();

                // Log token usage
                tracing::info!(
                    "AI completion used {} tokens with {} (cost: ${:.4})",
                    ai_response.tokens_used,
                    ai_response.model_used,
                    ai_response.cost
                );

                Ok(Some(tower_lsp::lsp_types::CompletionResponse::Array(completions)))
            }
            Err(e) => {
                tracing::error!("AI completion failed: {}", e);
                self.client
                    .log_message(MessageType::WARNING, format!("AI completion failed: {}", e))
                    .await;
                Ok(None)
            }
        }
    }

    async fn code_action(&self, params: CodeActionParams) -> Result<Option<CodeActionResponse>> {
        let uri = &params.text_document.uri;
        let range = params.range;

        tracing::debug!("Code action requested for range: {:?}", range);

        // Get current context
        let context_cache = self.context_cache.read().await;
        let context = context_cache.current_context.clone();

        match self.ai_service.get_code_actions(uri, range, context).await {
            Ok(ai_actions) => {
                let code_actions: Vec<CodeActionOrCommand> = ai_actions
                    .into_iter()
                    .map(|action| {
                        CodeActionOrCommand::Command(Command {
                            title: action.title,
                            command: action.command,
                            arguments: Some(action.args),
                        })
                    })
                    .collect();

                Ok(Some(code_actions))
            }
            Err(e) => {
                tracing::error!("Code actions failed: {}", e);
                Ok(None)
            }
        }
    }

    async fn hover(&self, params: HoverParams) -> Result<Option<Hover>> {
        let uri = &params.text_document_position_params.text_document.uri;
        let position = params.text_document_position_params.position;

        // Get text at position for context
        let cache = self.document_cache.read().await;
        let text = match cache.get(uri) {
            Some(text) => text,
            None => return Ok(None),
        };

        // Extract word/symbol at position
        let word = extract_word_at_position(text, position);
        if word.is_empty() {
            return Ok(None);
        }

        let language = get_language_from_uri(uri);

        // Get AI explanation
        match self.ai_service.explain_code(&word, &language).await {
            Ok(explanation) => {
                let hover_content = HoverContents::Scalar(MarkedString::String(explanation));
                Ok(Some(Hover {
                    contents: hover_content,
                    range: None,
                }))
            }
            Err(_) => Ok(None),
        }
    }

    async fn execute_command(&self, params: ExecuteCommandParams) -> Result<Option<serde_json::Value>> {
        tracing::info!("Executing command: {}", params.command);

        match params.command.as_str() {
            "devys.explain" => {
                if let Some(args) = params.arguments {
                    if let Some(code) = args.get(0).and_then(|v| v.as_str()) {
                        let language = args.get(1).and_then(|v| v.as_str()).unwrap_or("text");
                        
                        match self.ai_service.explain_code(code, language).await {
                            Ok(explanation) => {
                                self.client
                                    .show_message(MessageType::INFO, format!("Explanation: {}", explanation))
                                    .await;
                                return Ok(Some(serde_json::json!({"explanation": explanation})));
                            }
                            Err(e) => {
                                self.client
                                    .show_message(MessageType::ERROR, format!("Failed to explain: {}", e))
                                    .await;
                            }
                        }
                    }
                }
            }
            "devys.refactor" => {
                if let Some(args) = params.arguments {
                    if let Some(code) = args.get(0).and_then(|v| v.as_str()) {
                        let language = args.get(1).and_then(|v| v.as_str()).unwrap_or("text");
                        let instruction = args.get(2).and_then(|v| v.as_str()).unwrap_or("Improve this code");
                        
                        match self.ai_service.refactor_code(code, language, instruction).await {
                            Ok(refactored) => {
                                return Ok(Some(serde_json::json!({"refactored_code": refactored})));
                            }
                            Err(e) => {
                                self.client
                                    .show_message(MessageType::ERROR, format!("Failed to refactor: {}", e))
                                    .await;
                            }
                        }
                    }
                }
            }
            _ => {
                self.client
                    .show_message(MessageType::WARNING, format!("Unknown command: {}", params.command))
                    .await;
            }
        }

        Ok(None)
    }
}

impl DevysLspServer {
    fn new(client: Client) -> Self {
        Self {
            client,
            ai_service: AiService::new(),
            document_cache: RwLock::new(HashMap::new()),
            context_cache: RwLock::new(ContextCache::default()),
        }
    }
}

// Helper functions
fn get_language_from_uri(uri: &Url) -> String {
    if let Some(path) = uri.path().split('/').last() {
        if let Some(extension) = path.split('.').last() {
            return match extension {
                "rs" => "rust",
                "ts" => "typescript", 
                "js" => "javascript",
                "py" => "python",
                "go" => "go",
                "java" => "java",
                "cpp" | "cc" => "cpp",
                "c" => "c",
                "md" => "markdown",
                _ => "text",
            }.to_string();
        }
    }
    "text".to_string()
}

fn extract_word_at_position(text: &str, position: Position) -> String {
    let lines: Vec<&str> = text.lines().collect();
    if position.line as usize >= lines.len() {
        return String::new();
    }

    let line = lines[position.line as usize];
    let char_pos = position.character as usize;
    
    if char_pos >= line.len() {
        return String::new();
    }

    // Find word boundaries
    let mut start = char_pos;
    let mut end = char_pos;
    
    let chars: Vec<char> = line.chars().collect();
    
    // Move start backward to word boundary
    while start > 0 && (chars[start - 1].is_alphanumeric() || chars[start - 1] == '_') {
        start -= 1;
    }
    
    // Move end forward to word boundary
    while end < chars.len() && (chars[end].is_alphanumeric() || chars[end] == '_') {
        end += 1;
    }
    
    chars[start..end].iter().collect()
}

fn apply_text_change(text: &str, change: &str, range: Range) -> String {
    let lines: Vec<&str> = text.lines().collect();
    let mut result = String::new();
    
    // Add lines before the change
    for (i, line) in lines.iter().enumerate() {
        if i < range.start.line as usize {
            result.push_str(line);
            result.push('\n');
        } else if i == range.start.line as usize {
            // Handle the line containing the start of the change
            let start_char = range.start.character as usize;
            let line_chars: Vec<char> = line.chars().collect();
            result.push_str(&line_chars[..start_char.min(line_chars.len())].iter().collect::<String>());
            
            if range.start.line == range.end.line {
                // Single line change
                result.push_str(change);
                let end_char = range.end.character as usize;
                result.push_str(&line_chars[end_char.min(line_chars.len())..].iter().collect::<String>());
                result.push('\n');
            } else {
                // Multi-line change starts here
                result.push_str(change);
            }
            break;
        }
    }
    
    // Add lines after the change (if multi-line)
    if range.start.line != range.end.line {
        for (i, line) in lines.iter().enumerate() {
            if i > range.end.line as usize {
                result.push_str(line);
                result.push('\n');
            } else if i == range.end.line as usize {
                let end_char = range.end.character as usize;
                let line_chars: Vec<char> = line.chars().collect();
                result.push_str(&line_chars[end_char.min(line_chars.len())..].iter().collect::<String>());
                result.push('\n');
            }
        }
    }
    
    // Remove trailing newline if original didn't have it
    if !text.ends_with('\n') && result.ends_with('\n') {
        result.pop();
    }
    
    result
}

#[tokio::main]
async fn main() {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .with_ansi(false)
        .init();

    let stdin = tokio::io::stdin();
    let stdout = tokio::io::stdout();

    let (service, socket) = LspService::build(|client| DevysLspServer::new(client))
        .custom_method("devys/getContext", |server: &DevysLspServer, params| async move {
            // Custom method to get current context
            let cache = server.context_cache.read().await;
            Ok(serde_json::json!({
                "context": cache.current_context,
                "token_count": cache.token_count,
                "last_update": cache.last_update.elapsed().as_secs()
            }))
        })
        .finish();

    tracing::info!("Starting Devys LSP Server...");
    Server::new(stdin, stdout, socket).serve(service).await;
}