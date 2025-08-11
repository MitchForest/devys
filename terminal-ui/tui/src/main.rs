use anyhow::Result;
use clap::{Parser, Subcommand};
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::{Backend, CrosstermBackend},
    layout::{Alignment, Constraint, Direction, Layout, Margin},
    style::{Color, Modifier, Style},
    text::{Line, Span, Text},
    widgets::{
        Block, Borders, Clear, Gauge, List, ListItem, ListState, Paragraph, Scrollbar,
        ScrollbarOrientation, ScrollbarState, Wrap,
    },
    Frame, Terminal,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    io,
    time::{Duration, Instant},
};
use tui_input::{backend::crossterm::EventHandler, Input};

#[derive(Parser)]
#[command(name = "devys-context")]
#[command(about = "Devys Context Builder TUI")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
    
    /// Control plane URL
    #[arg(long, default_value = "http://localhost:3000")]
    control_plane: String,
    
    /// Auto-refresh interval in seconds
    #[arg(long, default_value = "2")]
    refresh_interval: u64,
}

#[derive(Subcommand)]
enum Commands {
    /// Start in watch mode (auto-refresh)
    Watch,
    /// Interactive context builder
    Build,
    /// Show current status
    Status,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ContextState {
    files: Vec<FileContext>,
    total_tokens: usize,
    max_tokens: usize,
    model: String,
    estimated_cost: f32,
    context_hash: String,
    created_at: chrono::DateTime<chrono::Utc>,
    last_updated: chrono::DateTime<chrono::Utc>,
    relevance_scores: HashMap<String, f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FileContext {
    path: String,
    included: bool,
    tokens: usize,
    relevance_score: f32,
    file_type: String,
    last_modified: chrono::DateTime<chrono::Utc>,
    size_bytes: usize,
    lines: usize,
    symbols: Vec<String>,
    dependencies: Vec<String>,
    working_set: bool,
}

#[derive(Debug)]
struct App {
    context_state: ContextState,
    list_state: ListState,
    scroll_state: ScrollbarState,
    input: Input,
    input_mode: InputMode,
    show_help: bool,
    show_filter_dialog: bool,
    filter_query: String,
    filtered_files: Vec<usize>,
    last_refresh: Instant,
    control_plane_url: String,
    client: reqwest::Client,
    error_message: Option<String>,
    success_message: Option<String>,
    view_mode: ViewMode,
}

#[derive(Debug, PartialEq)]
enum InputMode {
    Normal,
    Filter,
}

#[derive(Debug, PartialEq, Clone)]
enum ViewMode {
    List,
    Details,
    Tree,
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
            created_at: chrono::Utc::now(),
            last_updated: chrono::Utc::now(),
            relevance_scores: HashMap::new(),
        }
    }
}

impl App {
    fn new(control_plane_url: String) -> Self {
        let mut list_state = ListState::default();
        list_state.select(Some(0));
        
        Self {
            context_state: ContextState::default(),
            list_state,
            scroll_state: ScrollbarState::default(),
            input: Input::default(),
            input_mode: InputMode::Normal,
            show_help: false,
            show_filter_dialog: false,
            filter_query: String::new(),
            filtered_files: vec![],
            last_refresh: Instant::now(),
            control_plane_url,
            client: reqwest::Client::new(),
            error_message: None,
            success_message: None,
            view_mode: ViewMode::List,
        }
    }

    async fn refresh_data(&mut self) -> Result<()> {
        match self.fetch_context_state().await {
            Ok(state) => {
                self.context_state = state;
                self.apply_filter();
                self.error_message = None;
                self.last_refresh = Instant::now();
            }
            Err(e) => {
                self.error_message = Some(format!("Failed to refresh: {}", e));
            }
        }
        Ok(())
    }

    async fn fetch_context_state(&self) -> Result<ContextState> {
        let response = self
            .client
            .get(&format!("{}/api/context/current", self.control_plane_url))
            .send()
            .await?;

        if !response.status().is_success() {
            return Err(anyhow::anyhow!("API returned error: {}", response.status()));
        }

        let state: ContextState = response.json().await?;
        Ok(state)
    }

    async fn toggle_file_inclusion(&mut self, file_path: &str) -> Result<()> {
        let response = self
            .client
            .post(&format!("{}/api/context/toggle-file", self.control_plane_url))
            .json(&serde_json::json!({"path": file_path}))
            .send()
            .await?;

        if response.status().is_success() {
            self.success_message = Some("File inclusion toggled".to_string());
            self.refresh_data().await?;
        } else {
            self.error_message = Some("Failed to toggle file inclusion".to_string());
        }

        Ok(())
    }

    async fn optimize_context(&mut self) -> Result<()> {
        let response = self
            .client
            .post(&format!("{}/api/context/optimize", self.control_plane_url))
            .send()
            .await?;

        if response.status().is_success() {
            self.success_message = Some("Context optimized".to_string());
            self.refresh_data().await?;
        } else {
            self.error_message = Some("Failed to optimize context".to_string());
        }

        Ok(())
    }

    fn apply_filter(&mut self) {
        if self.filter_query.is_empty() {
            self.filtered_files = (0..self.context_state.files.len()).collect();
        } else {
            let query = self.filter_query.to_lowercase();
            self.filtered_files = self
                .context_state
                .files
                .iter()
                .enumerate()
                .filter(|(_, file)| {
                    file.path.to_lowercase().contains(&query)
                        || file.file_type.to_lowercase().contains(&query)
                        || file.symbols.iter().any(|s| s.to_lowercase().contains(&query))
                })
                .map(|(i, _)| i)
                .collect();
        }

        // Update scroll state
        self.scroll_state = self.scroll_state.content_length(self.filtered_files.len());

        // Ensure selection is valid
        if let Some(selected) = self.list_state.selected() {
            if selected >= self.filtered_files.len() {
                self.list_state.select(if self.filtered_files.is_empty() {
                    None
                } else {
                    Some(0)
                });
            }
        } else if !self.filtered_files.is_empty() {
            self.list_state.select(Some(0));
        }
    }

    fn next_file(&mut self) {
        if self.filtered_files.is_empty() {
            return;
        }
        
        let i = match self.list_state.selected() {
            Some(i) => (i + 1) % self.filtered_files.len(),
            None => 0,
        };
        self.list_state.select(Some(i));
        self.scroll_state = self.scroll_state.position(i);
    }

    fn previous_file(&mut self) {
        if self.filtered_files.is_empty() {
            return;
        }
        
        let i = match self.list_state.selected() {
            Some(i) => {
                if i == 0 {
                    self.filtered_files.len() - 1
                } else {
                    i - 1
                }
            }
            None => 0,
        };
        self.list_state.select(Some(i));
        self.scroll_state = self.scroll_state.position(i);
    }

    fn get_selected_file(&self) -> Option<&FileContext> {
        if let Some(selected_index) = self.list_state.selected() {
            if let Some(&file_index) = self.filtered_files.get(selected_index) {
                return self.context_state.files.get(file_index);
            }
        }
        None
    }

    fn get_model_recommendation(&self) -> (&str, &str, f32) {
        let tokens = self.context_state.total_tokens;
        match tokens {
            t if t < 30000 => ("claude-3-5-haiku", "Fast & cheap", t as f32 * 0.0000008),
            t if t < 150000 => ("claude-3-5-sonnet", "Best for code", t as f32 * 0.000003),
            t if t < 900000 => ("gemini-2.0-flash", "Large context, free", 0.0),
            _ => ("gemini-2.0-flash-thinking", "Massive context", 0.0),
        }
    }
}

fn run_app<B: Backend>(
    terminal: &mut Terminal<B>,
    mut app: App,
    refresh_interval: Duration,
) -> Result<()> {
    let mut last_tick = Instant::now();

    loop {
        terminal.draw(|f| ui(f, &mut app))?;

        let timeout = refresh_interval
            .checked_sub(last_tick.elapsed())
            .unwrap_or_else(|| Duration::from_secs(0));

        if crossterm::event::poll(timeout)? {
            if let Event::Key(key) = event::read()? {
                match app.input_mode {
                    InputMode::Normal => match key.code {
                        KeyCode::Char('q') => return Ok(()),
                        KeyCode::Char('h') => app.show_help = !app.show_help,
                        KeyCode::Char('r') => {
                            tokio::spawn(async move {
                                // In real implementation, this would trigger a refresh
                                // For now, we'll handle it in the main loop
                            });
                        }
                        KeyCode::Char('f') => {
                            app.show_filter_dialog = true;
                            app.input_mode = InputMode::Filter;
                            app.input.reset();
                        }
                        KeyCode::Char('o') => {
                            tokio::spawn(async move {
                                // Trigger context optimization
                            });
                        }
                        KeyCode::Char(' ') => {
                            if let Some(file) = app.get_selected_file() {
                                let file_path = file.path.clone();
                                tokio::spawn(async move {
                                    // Toggle file inclusion
                                });
                            }
                        }
                        KeyCode::Char('1') => app.view_mode = ViewMode::List,
                        KeyCode::Char('2') => app.view_mode = ViewMode::Details,
                        KeyCode::Char('3') => app.view_mode = ViewMode::Tree,
                        KeyCode::Up | KeyCode::Char('k') => app.previous_file(),
                        KeyCode::Down | KeyCode::Char('j') => app.next_file(),
                        KeyCode::PageUp => {
                            for _ in 0..10 {
                                app.previous_file();
                            }
                        }
                        KeyCode::PageDown => {
                            for _ in 0..10 {
                                app.next_file();
                            }
                        }
                        KeyCode::Esc => {
                            app.error_message = None;
                            app.success_message = None;
                        }
                        _ => {}
                    },
                    InputMode::Filter => match key.code {
                        KeyCode::Enter => {
                            app.filter_query = app.input.value().to_string();
                            app.apply_filter();
                            app.show_filter_dialog = false;
                            app.input_mode = InputMode::Normal;
                        }
                        KeyCode::Esc => {
                            app.show_filter_dialog = false;
                            app.input_mode = InputMode::Normal;
                        }
                        _ => {
                            app.input.handle_event(&Event::Key(key));
                        }
                    },
                }
            }
        }

        if last_tick.elapsed() >= refresh_interval {
            // In a full async implementation, we'd refresh data here
            last_tick = Instant::now();
        }
    }
}

fn ui(f: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Header
            Constraint::Length(3), // Token usage
            Constraint::Min(0),    // Main content
            Constraint::Length(3), // Footer
        ])
        .split(f.size());

    // Header
    render_header(f, chunks[0], app);

    // Token usage
    render_token_usage(f, chunks[1], app);

    // Main content based on view mode
    match app.view_mode {
        ViewMode::List => render_file_list(f, chunks[2], app),
        ViewMode::Details => render_details_view(f, chunks[2], app),
        ViewMode::Tree => render_tree_view(f, chunks[2], app),
    }

    // Footer
    render_footer(f, chunks[3], app);

    // Overlays
    if app.show_help {
        render_help_popup(f, app);
    }

    if app.show_filter_dialog {
        render_filter_dialog(f, app);
    }

    if app.error_message.is_some() || app.success_message.is_some() {
        render_message_popup(f, app);
    }
}

fn render_header(f: &mut Frame, area: ratatui::prelude::Rect, app: &App) {
    let header = Paragraph::new(format!(
        "Devys Context Builder [{}] - {} files ({} included)",
        match app.view_mode {
            ViewMode::List => "List",
            ViewMode::Details => "Details",
            ViewMode::Tree => "Tree",
        },
        app.context_state.files.len(),
        app.context_state.files.iter().filter(|f| f.included).count()
    ))
    .style(Style::default().fg(Color::Cyan))
    .block(Block::default().borders(Borders::ALL))
    .alignment(Alignment::Center);

    f.render_widget(header, area);
}

fn render_token_usage(f: &mut Frame, area: ratatui::prelude::Rect, app: &App) {
    let usage_ratio = app.context_state.total_tokens as f64 / app.context_state.max_tokens as f64;
    let (model, reason, cost) = app.get_model_recommendation();
    
    let color = match (usage_ratio * 100.0) as u16 {
        0..=60 => Color::Green,
        61..=85 => Color::Yellow,
        _ => Color::Red,
    };

    let gauge = Gauge::default()
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!(
                    "Tokens: {}/{} | Model: {} | {} | Cost: ${:.4}",
                    app.context_state.total_tokens,
                    app.context_state.max_tokens,
                    app.context_state.model,
                    reason,
                    cost
                ))
        )
        .gauge_style(Style::default().fg(color))
        .percent((usage_ratio * 100.0) as u16)
        .label(format!("{:.1}%", usage_ratio * 100.0));

    f.render_widget(gauge, area);
}

fn render_file_list(f: &mut Frame, area: ratatui::prelude::Rect, app: &mut App) {
    let files: Vec<ListItem> = app
        .filtered_files
        .iter()
        .map(|&i| {
            let file = &app.context_state.files[i];
            let inclusion_indicator = if file.included { "✓" } else { "○" };
            let working_set_indicator = if file.working_set { "📝" } else { " " };
            
            // Relevance score bar
            let score_filled = (file.relevance_score * 10.0) as usize;
            let score_bar = format!(
                "[{}{}]",
                "█".repeat(score_filled.min(10)),
                "░".repeat(10 - score_filled.min(10))
            );

            let style = if file.included {
                Style::default().fg(Color::Green)
            } else {
                Style::default().fg(Color::Gray)
            };

            ListItem::new(vec![Line::from(vec![
                Span::styled(format!("{} {}", inclusion_indicator, working_set_indicator), style),
                Span::styled(score_bar, Style::default().fg(Color::Blue)),
                Span::styled(format!(" {} ", file.path), style),
                Span::styled(format!("({} tok)", file.tokens), Style::default().fg(Color::Yellow)),
                Span::styled(format!(" [{}]", file.file_type), Style::default().fg(Color::Magenta)),
                Span::styled(format!(" {:.2}", file.relevance_score), Style::default().fg(Color::Cyan)),
            ])]).style(style)
        })
        .collect();

    let files_widget = List::new(files)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!(
                    "Files ({}{})",
                    if app.filter_query.is_empty() { 
                        String::new() 
                    } else { 
                        format!("filtered by '{}' - ", app.filter_query) 
                    },
                    app.filtered_files.len()
                ))
        )
        .highlight_style(
            Style::default()
                .bg(Color::Blue)
                .add_modifier(Modifier::BOLD)
        );

    f.render_stateful_widget(files_widget, area, &mut app.list_state);

    // Render scrollbar
    let scrollbar = Scrollbar::default()
        .orientation(ScrollbarOrientation::VerticalRight)
        .begin_symbol(Some("↑"))
        .end_symbol(Some("↓"));
    f.render_stateful_widget(
        scrollbar,
        area.inner(&Margin { vertical: 1, horizontal: 0 }),
        &mut app.scroll_state,
    );
}

fn render_details_view(f: &mut Frame, area: ratatui::prelude::Rect, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(area);

    // Left side: file list (simplified)
    render_file_list(f, chunks[0], app);

    // Right side: details for selected file
    if let Some(file) = app.get_selected_file() {
        let details = vec![
            format!("Path: {}", file.path),
            format!("Type: {}", file.file_type),
            format!("Size: {} bytes ({} lines)", file.size_bytes, file.lines),
            format!("Tokens: {}", file.tokens),
            format!("Relevance: {:.2}", file.relevance_score),
            format!("Working Set: {}", if file.working_set { "Yes" } else { "No" }),
            format!("Included: {}", if file.included { "Yes" } else { "No" }),
            format!("Last Modified: {}", file.last_modified.format("%Y-%m-%d %H:%M:%S")),
            String::new(),
            format!("Symbols ({}):", file.symbols.len()),
        ];

        let mut all_details = details;
        for symbol in &file.symbols {
            all_details.push(format!("  • {}", symbol));
        }

        if !file.dependencies.is_empty() {
            all_details.push(String::new());
            all_details.push(format!("Dependencies ({}):", file.dependencies.len()));
            for dep in &file.dependencies {
                all_details.push(format!("  → {}", dep));
            }
        }

        let details_text = all_details.join("\n");
        let details_widget = Paragraph::new(details_text)
            .block(Block::default().borders(Borders::ALL).title("File Details"))
            .wrap(Wrap { trim: true });

        f.render_widget(details_widget, chunks[1]);
    } else {
        let no_selection = Paragraph::new("No file selected")
            .block(Block::default().borders(Borders::ALL).title("File Details"))
            .alignment(Alignment::Center);
        f.render_widget(no_selection, chunks[1]);
    }
}

fn render_tree_view(f: &mut Frame, area: ratatui::prelude::Rect, app: &mut App) {
    // Build tree structure
    let mut tree_items = Vec::new();
    let mut directories = std::collections::BTreeMap::new();

    // Group files by directory
    for (i, file) in app.context_state.files.iter().enumerate() {
        let path_parts: Vec<&str> = file.path.split('/').collect();
        for j in 0..path_parts.len() {
            let current_path = path_parts[0..=j].join("/");
            directories.entry(current_path.clone()).or_insert_with(Vec::new);
            if j == path_parts.len() - 1 {
                directories.get_mut(&current_path).unwrap().push(i);
            }
        }
    }

    // Build tree display
    let mut sorted_paths: Vec<_> = directories.keys().collect();
    sorted_paths.sort();

    for path in sorted_paths {
        let depth = path.matches('/').count();
        let indent = "  ".repeat(depth);
        let name = path.split('/').last().unwrap_or(path);
        
        if let Some(file_indices) = directories.get(path) {
            if file_indices.is_empty() {
                // Directory
                tree_items.push(ListItem::new(format!("{}📁 {}/", indent, name))
                    .style(Style::default().fg(Color::Yellow)));
            } else {
                // Files in this directory
                for &file_idx in file_indices {
                    let file = &app.context_state.files[file_idx];
                    if file.path == *path {  // This is the file itself, not just in the directory
                        let inclusion_indicator = if file.included { "✓" } else { "○" };
                        let icon = match file.file_type.as_str() {
                            "typescript" | "javascript" => "📄",
                            "rust" => "🦀",
                            "python" => "🐍",
                            "markdown" => "📝",
                            _ => "📄",
                        };
                        
                        let style = if file.included {
                            Style::default().fg(Color::Green)
                        } else {
                            Style::default().fg(Color::Gray)
                        };

                        tree_items.push(ListItem::new(format!(
                            "{}{} {} {} ({} tok)",
                            indent, inclusion_indicator, icon, name, file.tokens
                        )).style(style));
                    }
                }
            }
        }
    }

    let tree_widget = List::new(tree_items)
        .block(Block::default().borders(Borders::ALL).title("File Tree"));

    f.render_widget(tree_widget, area);
}

fn render_footer(f: &mut Frame, area: ratatui::prelude::Rect, app: &App) {
    let help_text = match app.input_mode {
        InputMode::Normal => "q: Quit | h: Help | r: Refresh | f: Filter | Space: Toggle | o: Optimize | 1-3: View modes",
        InputMode::Filter => "Enter: Apply filter | Esc: Cancel",
    };

    let footer = Paragraph::new(help_text)
        .style(Style::default().fg(Color::Gray))
        .block(Block::default().borders(Borders::ALL))
        .alignment(Alignment::Center);

    f.render_widget(footer, area);
}

fn render_help_popup(f: &mut Frame, _app: &App) {
    let block = Block::default()
        .title("Help")
        .borders(Borders::ALL)
        .style(Style::default().bg(Color::Black));

    let area = centered_rect(60, 70, f.size());
    f.render_widget(Clear, area);
    f.render_widget(block, area);

    let help_text = vec![
        "Devys Context Builder Help",
        "",
        "Navigation:",
        "  ↑/k, ↓/j    - Move up/down",
        "  Page Up/Down - Move 10 items",
        "",
        "Actions:",
        "  Space       - Toggle file inclusion",
        "  f           - Filter files",
        "  r           - Refresh data",
        "  o           - Optimize context",
        "",
        "View Modes:",
        "  1           - List view",
        "  2           - Details view", 
        "  3           - Tree view",
        "",
        "Other:",
        "  h           - Toggle this help",
        "  q           - Quit",
        "  Esc         - Clear messages",
    ];

    let paragraph = Paragraph::new(help_text.join("\n"))
        .style(Style::default().fg(Color::White))
        .alignment(Alignment::Left)
        .wrap(Wrap { trim: true });

    f.render_widget(paragraph, area.inner(&Margin { vertical: 1, horizontal: 2 }));
}

fn render_filter_dialog(f: &mut Frame, app: &App) {
    let block = Block::default()
        .title("Filter Files")
        .borders(Borders::ALL)
        .style(Style::default().bg(Color::Black));

    let area = centered_rect(50, 20, f.size());
    f.render_widget(Clear, area);
    f.render_widget(block, area);

    let input_area = area.inner(&Margin { vertical: 2, horizontal: 2 });
    
    let input_paragraph = Paragraph::new(app.input.value())
        .style(Style::default().fg(Color::Yellow))
        .block(Block::default().borders(Borders::ALL).title("Search"));

    f.render_widget(input_paragraph, input_area);

    // Set cursor position
    f.set_cursor(
        input_area.x + app.input.visual_cursor() as u16 + 1,
        input_area.y + 1,
    );
}

fn render_message_popup(f: &mut Frame, app: &App) {
    let (message, color) = if let Some(error) = &app.error_message {
        (error.as_str(), Color::Red)
    } else if let Some(success) = &app.success_message {
        (success.as_str(), Color::Green)
    } else {
        return;
    };

    let block = Block::default()
        .title(if app.error_message.is_some() { "Error" } else { "Success" })
        .borders(Borders::ALL)
        .style(Style::default().bg(Color::Black).fg(color));

    let area = centered_rect(40, 15, f.size());
    f.render_widget(Clear, area);
    f.render_widget(block, area);

    let paragraph = Paragraph::new(message)
        .style(Style::default().fg(color))
        .alignment(Alignment::Center)
        .wrap(Wrap { trim: true });

    f.render_widget(paragraph, area.inner(&Margin { vertical: 1, horizontal: 2 }));
}

fn centered_rect(percent_x: u16, percent_y: u16, r: ratatui::prelude::Rect) -> ratatui::prelude::Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(r);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(popup_layout[1])[1]
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    match cli.command {
        Some(Commands::Status) => {
            // Just print status and exit
            let client = reqwest::Client::new();
            match client
                .get(&format!("{}/api/context/current", cli.control_plane))
                .send()
                .await
            {
                Ok(response) => {
                    if let Ok(state) = response.json::<ContextState>().await {
                        println!("Context Status:");
                        println!("  Files: {} ({} included)", 
                            state.files.len(), 
                            state.files.iter().filter(|f| f.included).count());
                        println!("  Tokens: {}/{}", state.total_tokens, state.max_tokens);
                        println!("  Model: {}", state.model);
                        println!("  Est. Cost: ${:.4}", state.estimated_cost);
                    }
                }
                Err(e) => println!("Error: {}", e),
            }
            return Ok(());
        }
        _ => {}
    }

    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app and run
    let app = App::new(cli.control_plane);
    let refresh_interval = Duration::from_secs(cli.refresh_interval);
    let res = run_app(&mut terminal, app, refresh_interval);

    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    if let Err(err) = res {
        println!("{:?}", err);
    }

    Ok(())
}