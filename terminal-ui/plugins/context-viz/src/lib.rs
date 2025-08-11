use zellij_tile::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use chrono::{DateTime, Utc};

#[derive(Default, Debug)]
struct ContextVisualizerPlugin {
    current_context: ContextState,
    token_count: usize,
    file_scores: HashMap<String, f32>,
    selected_file_index: usize,
    view_mode: ViewMode,
    show_details: bool,
    scroll_offset: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ContextState {
    files: Vec<FileContext>,
    total_tokens: usize,
    max_tokens: usize,
    model: String,
    estimated_cost: f32,
    context_hash: String,
    created_at: DateTime<Utc>,
    last_updated: DateTime<Utc>,
    relevance_scores: HashMap<String, f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FileContext {
    path: String,
    included: bool,
    tokens: usize,
    relevance_score: f32,
    file_type: String,
    last_modified: DateTime<Utc>,
    size_bytes: usize,
    lines: usize,
    symbols: Vec<String>,
    dependencies: Vec<String>,
    working_set: bool,
}

#[derive(Debug, Clone, PartialEq)]
enum ViewMode {
    List,
    Tree,
    Heatmap,
    Dependencies,
}

impl Default for ContextState {
    fn default() -> Self {
        Self {
            files: vec![],
            total_tokens: 0,
            max_tokens: 200000,
            model: "claude-3-5-sonnet".to_string(),
            estimated_cost: 0.0,
            context_hash: String::new(),
            created_at: Utc::now(),
            last_updated: Utc::now(),
            relevance_scores: HashMap::new(),
        }
    }
}

impl Default for ViewMode {
    fn default() -> Self {
        ViewMode::List
    }
}

register_plugin!(ContextVisualizerPlugin);

impl ZellijPlugin for ContextVisualizerPlugin {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        // Initialize with sample data for demonstration
        self.initialize_sample_data();

        // Subscribe to events
        subscribe(&[EventType::Key, EventType::Timer]);
        
        // Start refresh timer
        set_timeout(2.0);

        // Request permissions
        request_permission(&[PermissionType::ReadApplicationState]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::Key(key) => {
                match key {
                    Key::Up => {
                        if self.selected_file_index > 0 {
                            self.selected_file_index -= 1;
                        }
                        true
                    }
                    Key::Down => {
                        if self.selected_file_index < self.current_context.files.len().saturating_sub(1) {
                            self.selected_file_index += 1;
                        }
                        true
                    }
                    Key::PageUp => {
                        self.scroll_offset = self.scroll_offset.saturating_sub(10);
                        true
                    }
                    Key::PageDown => {
                        self.scroll_offset += 10;
                        true
                    }
                    Key::Char('1') => {
                        self.view_mode = ViewMode::List;
                        true
                    }
                    Key::Char('2') => {
                        self.view_mode = ViewMode::Tree;
                        true
                    }
                    Key::Char('3') => {
                        self.view_mode = ViewMode::Heatmap;
                        true
                    }
                    Key::Char('4') => {
                        self.view_mode = ViewMode::Dependencies;
                        true
                    }
                    Key::Char('d') => {
                        self.show_details = !self.show_details;
                        true
                    }
                    Key::Char('r') => {
                        self.refresh_context();
                        true
                    }
                    Key::Char(' ') => {
                        self.toggle_file_inclusion();
                        true
                    }
                    Key::Char('o') => {
                        self.optimize_context();
                        true
                    }
                    _ => false
                }
            }
            Event::Timer(_) => {
                // Refresh context data
                self.request_context_update();
                set_timeout(2.0);
                true
            }
            Event::CustomMessage(message) => {
                self.handle_context_update(&message.payload);
                true
            }
            _ => false
        }
    }

    fn render(&mut self, rows: usize, cols: usize) {
        // Clear screen
        for y in 0..rows {
            print_text_with_coordinates(
                Text::new(" ".repeat(cols)),
                0,
                y,
                Some(Color::Rgb(200, 200, 200)),
                Some(Color::Rgb(15, 20, 25))
            );
        }

        let mut current_row = 0;

        // Header
        current_row += self.render_header(current_row, cols);
        current_row += 1;

        // Token usage bar
        current_row += self.render_token_usage(current_row, cols);
        current_row += 1;

        // Model recommendation
        current_row += self.render_model_recommendation(current_row, cols);
        current_row += 1;

        // Context content based on view mode
        let remaining_rows = rows.saturating_sub(current_row + 1);
        match self.view_mode {
            ViewMode::List => self.render_file_list(current_row, cols, remaining_rows),
            ViewMode::Tree => self.render_file_tree(current_row, cols, remaining_rows),
            ViewMode::Heatmap => self.render_relevance_heatmap(current_row, cols, remaining_rows),
            ViewMode::Dependencies => self.render_dependency_graph(current_row, cols, remaining_rows),
        }

        // Footer
        self.render_footer(rows - 1, cols);
    }
}

impl ContextVisualizerPlugin {
    fn initialize_sample_data(&mut self) {
        let now = Utc::now();
        self.current_context = ContextState {
            files: vec![
                FileContext {
                    path: "src/main.rs".to_string(),
                    included: true,
                    tokens: 2450,
                    relevance_score: 0.95,
                    file_type: "rust".to_string(),
                    last_modified: now,
                    size_bytes: 15678,
                    lines: 234,
                    symbols: vec!["main".to_string(), "init".to_string(), "DevysCore".to_string()],
                    dependencies: vec!["src/lib.rs".to_string()],
                    working_set: true,
                },
                FileContext {
                    path: "src/agents/planner-agent.ts".to_string(),
                    included: true,
                    tokens: 3200,
                    relevance_score: 0.87,
                    file_type: "typescript".to_string(),
                    last_modified: now,
                    size_bytes: 12456,
                    lines: 189,
                    symbols: vec!["PlannerAgent".to_string(), "plan".to_string()],
                    dependencies: vec!["src/agents/base-agent.ts".to_string()],
                    working_set: true,
                },
                FileContext {
                    path: "src/context/ai-context-builder.ts".to_string(),
                    included: true,
                    tokens: 4100,
                    relevance_score: 0.92,
                    file_type: "typescript".to_string(),
                    last_modified: now,
                    size_bytes: 18234,
                    lines: 298,
                    symbols: vec!["AIContextBuilder".to_string(), "buildContext".to_string()],
                    dependencies: vec!["src/services/context/context-service.ts".to_string()],
                    working_set: false,
                },
                FileContext {
                    path: "README.md".to_string(),
                    included: false,
                    tokens: 890,
                    relevance_score: 0.23,
                    file_type: "markdown".to_string(),
                    last_modified: now,
                    size_bytes: 4567,
                    lines: 89,
                    symbols: vec![],
                    dependencies: vec![],
                    working_set: false,
                },
            ],
            total_tokens: 10640,
            max_tokens: 200000,
            model: "claude-3-5-sonnet".to_string(),
            estimated_cost: 0.032,
            context_hash: "abc123def456".to_string(),
            created_at: now,
            last_updated: now,
            relevance_scores: HashMap::new(),
        };

        self.token_count = 10640;
    }

    fn render_header(&self, row: usize, cols: usize) -> usize {
        let title = "Context Visualizer";
        let mode_text = format!("[{}]", match self.view_mode {
            ViewMode::List => "List",
            ViewMode::Tree => "Tree", 
            ViewMode::Heatmap => "Heatmap",
            ViewMode::Dependencies => "Dependencies",
        });
        
        let timestamp = self.current_context.last_updated.format("%H:%M:%S").to_string();
        let header = format!("{} {} - Updated: {}", title, mode_text, timestamp);

        print_text_with_coordinates(
            Text::new(header),
            0,
            row,
            Some(Color::Rgb(100, 200, 255)),
            Some(Color::Rgb(30, 30, 40))
        );

        1
    }

    fn render_token_usage(&self, row: usize, cols: usize) -> usize {
        let usage_ratio = self.current_context.total_tokens as f32 / self.current_context.max_tokens as f32;
        let percentage = (usage_ratio * 100.0) as u16;
        
        let color = match percentage {
            0..=60 => Color::Rgb(0, 255, 0),   // Green
            61..=85 => Color::Rgb(255, 255, 0), // Yellow
            _ => Color::Rgb(255, 0, 0),         // Red
        };

        let usage_text = format!(
            "Tokens: {}/{} ({}%) | Model: {} | Cost: ${:.4}",
            self.current_context.total_tokens,
            self.current_context.max_tokens,
            percentage,
            self.current_context.model,
            self.current_context.estimated_cost
        );

        print_text_with_coordinates(
            Text::new(usage_text),
            0,
            row,
            Some(color),
            Some(Color::Rgb(25, 25, 25))
        );

        // Progress bar
        let bar_width = cols.min(80);
        let filled_width = (bar_width as f32 * usage_ratio) as usize;
        let bar = format!(
            "[{}{}]",
            "█".repeat(filled_width),
            "░".repeat(bar_width.saturating_sub(filled_width))
        );

        print_text_with_coordinates(
            Text::new(bar),
            0,
            row + 1,
            Some(color),
            Some(Color::Rgb(25, 25, 25))
        );

        2
    }

    fn render_model_recommendation(&self, row: usize, cols: usize) -> usize {
        let tokens = self.current_context.total_tokens;
        let (recommended_model, reason, estimated_cost) = self.recommend_model(tokens);
        
        let rec_text = format!(
            "💡 Recommended: {} - {} (Est: ${:.4})",
            recommended_model,
            reason,
            estimated_cost
        );

        let color = if recommended_model == self.current_context.model {
            Color::Rgb(0, 255, 0)
        } else {
            Color::Rgb(255, 255, 0)
        };

        print_text_with_coordinates(
            Text::new(rec_text),
            0,
            row,
            Some(color),
            Some(Color::Rgb(25, 25, 25))
        );

        1
    }

    fn render_file_list(&self, start_row: usize, cols: usize, max_rows: usize) {
        let header = format!("Files ({} included, {} total):", 
            self.current_context.files.iter().filter(|f| f.included).count(),
            self.current_context.files.len()
        );

        print_text_with_coordinates(
            Text::new(header),
            0,
            start_row,
            Some(Color::Rgb(200, 200, 200)),
            Some(Color::Rgb(25, 25, 25))
        );

        let available_rows = max_rows.saturating_sub(1);
        let visible_files: Vec<_> = self.current_context.files
            .iter()
            .enumerate()
            .skip(self.scroll_offset)
            .take(available_rows)
            .collect();

        for (i, (original_index, file)) in visible_files.iter().enumerate() {
            let row = start_row + 1 + i;
            let is_selected = *original_index == self.selected_file_index;
            
            let inclusion_indicator = if file.included { "✓" } else { "○" };
            let working_set_indicator = if file.working_set { "📝" } else { " " };
            
            // Relevance score visualization
            let score_bar = self.render_score_bar(file.relevance_score);
            
            let file_text = format!(
                "{} {} {} {} ({} tok) {} [{:.2}] {}",
                inclusion_indicator,
                working_set_indicator,
                score_bar,
                file.path,
                file.tokens,
                file.file_type.to_uppercase(),
                file.relevance_score,
                if self.show_details { 
                    format!("- {} lines, {} bytes", file.lines, file.size_bytes)
                } else { 
                    String::new() 
                }
            );

            let (fg_color, bg_color) = if is_selected {
                (Color::Rgb(0, 0, 0), Color::Rgb(100, 200, 255))
            } else if file.included {
                (Color::Rgb(0, 255, 0), Color::Rgb(20, 20, 20))
            } else {
                (Color::Rgb(128, 128, 128), Color::Rgb(20, 20, 20))
            };

            print_text_with_coordinates(
                Text::new(file_text),
                2,
                row,
                Some(fg_color),
                Some(bg_color)
            );

            // Show symbols if details enabled and selected
            if self.show_details && is_selected && !file.symbols.is_empty() {
                let symbols_text = format!("    Symbols: {}", file.symbols.join(", "));
                print_text_with_coordinates(
                    Text::new(symbols_text),
                    2,
                    row + 1,
                    Some(Color::Rgb(150, 150, 150)),
                    Some(Color::Rgb(25, 25, 25))
                );
            }
        }
    }

    fn render_file_tree(&self, start_row: usize, cols: usize, max_rows: usize) {
        let header = "File Tree View:";
        print_text_with_coordinates(
            Text::new(header),
            0,
            start_row,
            Some(Color::Rgb(200, 200, 200)),
            Some(Color::Rgb(25, 25, 25))
        );

        // Build tree structure from file paths
        let mut tree = std::collections::BTreeMap::new();
        for file in &self.current_context.files {
            let parts: Vec<&str> = file.path.split('/').collect();
            let mut current = &mut tree;
            
            for (i, part) in parts.iter().enumerate() {
                let entry = current.entry(part.to_string()).or_insert_with(|| {
                    if i == parts.len() - 1 {
                        // It's a file
                        TreeNode::File(file.clone())
                    } else {
                        // It's a directory
                        TreeNode::Directory(std::collections::BTreeMap::new())
                    }
                });
                
                if let TreeNode::Directory(ref mut dir) = entry {
                    current = dir;
                }
            }
        }

        let mut row = start_row + 1;
        self.render_tree_recursive(&tree, 0, &mut row, max_rows.saturating_sub(1), start_row + 1);
    }

    fn render_relevance_heatmap(&self, start_row: usize, cols: usize, max_rows: usize) {
        let header = "Relevance Heatmap:";
        print_text_with_coordinates(
            Text::new(header),
            0,
            start_row,
            Some(Color::Rgb(200, 200, 200)),
            Some(Color::Rgb(25, 25, 25))
        );

        let available_rows = max_rows.saturating_sub(1);
        let cell_width = 3;
        let cells_per_row = cols / cell_width;
        
        let mut sorted_files = self.current_context.files.clone();
        sorted_files.sort_by(|a, b| b.relevance_score.partial_cmp(&a.relevance_score).unwrap());

        for (i, file) in sorted_files.iter().enumerate().take(cells_per_row * available_rows) {
            let row = start_row + 1 + (i / cells_per_row);
            let col = (i % cells_per_row) * cell_width;

            let intensity = (file.relevance_score * 255.0) as u8;
            let color = Color::Rgb(intensity, intensity / 2, 0); // Heat map colors

            let cell_text = if file.included { "██" } else { "▓▓" };
            
            print_text_with_coordinates(
                Text::new(cell_text),
                col,
                row,
                Some(color),
                Some(Color::Rgb(20, 20, 20))
            );
        }

        // Legend
        let legend_row = start_row + available_rows - 2;
        print_text_with_coordinates(
            Text::new("Legend: ██ Included ▓▓ Excluded | Color intensity = relevance score"),
            0,
            legend_row,
            Some(Color::Rgb(150, 150, 150)),
            Some(Color::Rgb(25, 25, 25))
        );
    }

    fn render_dependency_graph(&self, start_row: usize, cols: usize, max_rows: usize) {
        let header = "Dependency Graph:";
        print_text_with_coordinates(
            Text::new(header),
            0,
            start_row,
            Some(Color::Rgb(200, 200, 200)),
            Some(Color::Rgb(25, 25, 25))
        );

        let mut row = start_row + 1;
        for file in &self.current_context.files {
            if row >= start_row + max_rows {
                break;
            }

            let inclusion_indicator = if file.included { "✓" } else { "○" };
            print_text_with_coordinates(
                Text::new(format!("{} {}", inclusion_indicator, file.path)),
                0,
                row,
                Some(if file.included { Color::Rgb(0, 255, 0) } else { Color::Rgb(128, 128, 128) }),
                Some(Color::Rgb(20, 20, 20))
            );
            row += 1;

            // Show dependencies
            for dep in &file.dependencies {
                if row >= start_row + max_rows {
                    break;
                }
                
                print_text_with_coordinates(
                    Text::new(format!("  └─ {}", dep)),
                    0,
                    row,
                    Some(Color::Rgb(100, 100, 200)),
                    Some(Color::Rgb(20, 20, 20))
                );
                row += 1;
            }
        }
    }

    fn render_footer(&self, row: usize, cols: usize) {
        let controls = format!(
            "1-4: View modes | ↑↓: Navigate | Space: Toggle | d: Details | r: Refresh | o: Optimize | Files: {}/{}",
            self.current_context.files.iter().filter(|f| f.included).count(),
            self.current_context.files.len()
        );

        let footer_text = if controls.len() > cols {
            format!("{}...", &controls[..cols.saturating_sub(3)])
        } else {
            controls
        };

        print_text_with_coordinates(
            Text::new(footer_text),
            0,
            row,
            Some(Color::Rgb(150, 150, 150)),
            Some(Color::Rgb(40, 40, 50))
        );
    }

    fn render_score_bar(&self, score: f32) -> String {
        let filled = (score * 10.0) as usize;
        format!("[{}{}]", "█".repeat(filled.min(10)), "░".repeat(10 - filled.min(10)))
    }

    fn render_tree_recursive(
        &self,
        tree: &std::collections::BTreeMap<String, TreeNode>,
        depth: usize,
        row: &mut usize,
        max_rows: usize,
        start_row: usize,
    ) {
        let indent = "  ".repeat(depth);
        
        for (name, node) in tree {
            if *row >= start_row + max_rows {
                break;
            }

            match node {
                TreeNode::Directory(subtree) => {
                    print_text_with_coordinates(
                        Text::new(format!("{}📁 {}/", indent, name)),
                        0,
                        *row,
                        Some(Color::Rgb(255, 255, 0)),
                        Some(Color::Rgb(20, 20, 20))
                    );
                    *row += 1;
                    self.render_tree_recursive(subtree, depth + 1, row, max_rows, start_row);
                }
                TreeNode::File(file) => {
                    let icon = match file.file_type.as_str() {
                        "typescript" | "javascript" => "📄",
                        "rust" => "🦀",
                        "python" => "🐍",
                        "markdown" => "📝",
                        _ => "📄",
                    };
                    
                    let inclusion_indicator = if file.included { "✓" } else { "○" };
                    
                    print_text_with_coordinates(
                        Text::new(format!("{}{} {} {} ({} tok)", indent, inclusion_indicator, icon, name, file.tokens)),
                        0,
                        *row,
                        Some(if file.included { Color::Rgb(0, 255, 0) } else { Color::Rgb(128, 128, 128) }),
                        Some(Color::Rgb(20, 20, 20))
                    );
                    *row += 1;
                }
            }
        }
    }

    fn recommend_model(&self, tokens: usize) -> (&str, &str, f32) {
        match tokens {
            t if t < 30000 => ("claude-3-5-haiku", "Fast & cheap for small context", t as f32 * 0.0000008),
            t if t < 150000 => ("claude-3-5-sonnet", "Best for code generation", t as f32 * 0.000003),
            t if t < 900000 => ("gemini-2.0-flash", "Large context, free", 0.0),
            _ => ("gemini-2.0-flash-thinking", "Massive context, reasoning", 0.0),
        }
    }

    fn toggle_file_inclusion(&mut self) {
        if let Some(file) = self.current_context.files.get_mut(self.selected_file_index) {
            file.included = !file.included;
            
            // Recalculate total tokens
            self.current_context.total_tokens = self.current_context.files
                .iter()
                .filter(|f| f.included)
                .map(|f| f.tokens)
                .sum();
            
            // Recalculate cost
            let (_, _, cost) = self.recommend_model(self.current_context.total_tokens);
            self.current_context.estimated_cost = cost;
            
            // Send update to control plane
            post_message_to("control-plane", format!(
                "context:toggle-file:{}:{}",
                file.path,
                file.included
            ));
        }
    }

    fn refresh_context(&mut self) {
        post_message_to("control-plane", "context:refresh".to_string());
    }

    fn optimize_context(&mut self) {
        post_message_to("control-plane", "context:optimize".to_string());
    }

    fn request_context_update(&mut self) {
        post_message_to("control-plane", "context:get-status".to_string());
    }

    fn handle_context_update(&mut self, payload: &str) {
        if let Ok(new_state) = serde_json::from_str::<ContextState>(payload) {
            self.current_context = new_state;
            self.token_count = self.current_context.total_tokens;
        }
    }
}

#[derive(Debug, Clone)]
enum TreeNode {
    Directory(std::collections::BTreeMap<String, TreeNode>),
    File(FileContext),
}