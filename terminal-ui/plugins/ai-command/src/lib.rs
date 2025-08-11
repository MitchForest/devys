use zellij_tile::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Default, Debug)]
struct AiCommandPlugin {
    workflow_state: WorkflowState,
    command_palette_visible: bool,
    selected_command: usize,
    commands: Vec<Command>,
    search_query: String,
    websocket_connected: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkflowState {
    mode: String,
    progress: f32,
    active_agents: Vec<String>,
    token_usage: TokenUsage,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TokenUsage {
    current: usize,
    total: usize,
    cost_usd: f32,
}

#[derive(Debug, Clone)]
struct Command {
    title: String,
    description: String,
    shortcut: String,
    category: CommandCategory,
}

#[derive(Debug, Clone)]
enum CommandCategory {
    Plan,
    Edit,
    Review,
    Grunt,
    Context,
    Model,
}

impl Default for WorkflowState {
    fn default() -> Self {
        Self {
            mode: "IDLE".to_string(),
            progress: 0.0,
            active_agents: vec![],
            token_usage: TokenUsage {
                current: 0,
                total: 0,
                cost_usd: 0.0,
            },
        }
    }
}

register_plugin!(AiCommandPlugin);

impl ZellijPlugin for AiCommandPlugin {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        // Initialize available commands
        self.commands = vec![
            Command {
                title: "AI Plan".to_string(),
                description: "Generate comprehensive task plan with AI".to_string(),
                shortcut: "Ctrl+P".to_string(),
                category: CommandCategory::Plan,
            },
            Command {
                title: "AI Edit".to_string(),
                description: "Execute code edits with AI assistance".to_string(),
                shortcut: "Ctrl+E".to_string(),
                category: CommandCategory::Edit,
            },
            Command {
                title: "AI Review".to_string(),
                description: "Review changes with AI analysis".to_string(),
                shortcut: "Ctrl+R".to_string(),
                category: CommandCategory::Review,
            },
            Command {
                title: "AI Complete".to_string(),
                description: "Smart code completion and suggestions".to_string(),
                shortcut: "Ctrl+Space".to_string(),
                category: CommandCategory::Edit,
            },
            Command {
                title: "Context View".to_string(),
                description: "Show current AI context and token usage".to_string(),
                shortcut: "Ctrl+C".to_string(),
                category: CommandCategory::Context,
            },
            Command {
                title: "Model Select".to_string(),
                description: "Choose AI model for next operation".to_string(),
                shortcut: "Ctrl+M".to_string(),
                category: CommandCategory::Model,
            },
            Command {
                title: "Grunt Format".to_string(),
                description: "Format code with local AI assistant".to_string(),
                shortcut: "Ctrl+G F".to_string(),
                category: CommandCategory::Grunt,
            },
            Command {
                title: "Grunt Test".to_string(),
                description: "Run tests with AI analysis".to_string(),
                shortcut: "Ctrl+G T".to_string(),
                category: CommandCategory::Grunt,
            },
        ];

        // Subscribe to key events
        subscribe(&[EventType::Key, EventType::Mouse]);

        // Request plugin permission for network access
        request_permission(&[PermissionType::ReadApplicationState]);

        // Attempt WebSocket connection to Control Plane
        self.connect_to_control_plane();
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::Key(key) => {
                match key {
                    // Toggle command palette with Ctrl+A
                    Key::Ctrl('a') => {
                        self.command_palette_visible = !self.command_palette_visible;
                        if self.command_palette_visible {
                            self.search_query.clear();
                            self.selected_command = 0;
                        }
                        true
                    }
                    // Handle navigation within command palette
                    _ if self.command_palette_visible => {
                        self.handle_palette_input(key)
                    }
                    // Handle direct shortcuts when palette is closed
                    Key::Ctrl('p') => {
                        self.execute_command("plan");
                        true
                    }
                    Key::Ctrl('e') => {
                        self.execute_command("edit");
                        true
                    }
                    Key::Ctrl('r') => {
                        self.execute_command("review");
                        true
                    }
                    Key::Ctrl('c') => {
                        self.execute_command("context");
                        true
                    }
                    Key::Ctrl('m') => {
                        self.execute_command("model");
                        true
                    }
                    _ => false
                }
            }
            Event::CustomMessage(message) => {
                // Handle WebSocket messages from Control Plane
                if let Ok(state) = serde_json::from_str::<WorkflowState>(&message.payload) {
                    self.workflow_state = state;
                    true
                } else {
                    false
                }
            }
            _ => false
        }
    }

    fn render(&mut self, rows: usize, cols: usize) {
        if self.command_palette_visible {
            self.render_command_palette(rows, cols);
        } else {
            self.render_status_bar(rows, cols);
        }
    }
}

impl AiCommandPlugin {
    fn connect_to_control_plane(&mut self) {
        // Send WebSocket connection request to control plane
        // This would be handled by Zellij's WebSocket capabilities
        post_message_to("control-plane", "connect".to_string());
        self.websocket_connected = true;
    }

    fn handle_palette_input(&mut self, key: Key) -> bool {
        match key {
            Key::Esc => {
                self.command_palette_visible = false;
                true
            }
            Key::Enter => {
                if !self.commands.is_empty() && self.selected_command < self.commands.len() {
                    let command = &self.commands[self.selected_command];
                    self.execute_command_by_title(&command.title);
                    self.command_palette_visible = false;
                }
                true
            }
            Key::Up => {
                if self.selected_command > 0 {
                    self.selected_command -= 1;
                }
                true
            }
            Key::Down => {
                if self.selected_command < self.commands.len().saturating_sub(1) {
                    self.selected_command += 1;
                }
                true
            }
            Key::Char(c) => {
                self.search_query.push(c);
                self.filter_commands();
                self.selected_command = 0;
                true
            }
            Key::Backspace => {
                self.search_query.pop();
                self.filter_commands();
                self.selected_command = 0;
                true
            }
            _ => false
        }
    }

    fn filter_commands(&mut self) {
        // Filter commands based on search query
        // This is a simple substring match - could be enhanced with fuzzy search
        if self.search_query.is_empty() {
            // Show all commands when no search query
            return;
        }
        
        let query = self.search_query.to_lowercase();
        self.commands.retain(|cmd| {
            cmd.title.to_lowercase().contains(&query) ||
            cmd.description.to_lowercase().contains(&query)
        });
    }

    fn execute_command(&mut self, command: &str) {
        match command {
            "plan" => {
                post_message_to("control-plane", "execute:plan".to_string());
            }
            "edit" => {
                post_message_to("control-plane", "execute:edit".to_string());
            }
            "review" => {
                post_message_to("control-plane", "execute:review".to_string());
            }
            "context" => {
                post_message_to("control-plane", "show:context".to_string());
            }
            "model" => {
                post_message_to("control-plane", "show:model-selector".to_string());
            }
            _ => {}
        }
    }

    fn execute_command_by_title(&mut self, title: &str) {
        let command = match title {
            "AI Plan" => "plan",
            "AI Edit" => "edit", 
            "AI Review" => "review",
            "Context View" => "context",
            "Model Select" => "model",
            "Grunt Format" => "grunt:format",
            "Grunt Test" => "grunt:test",
            _ => return,
        };
        self.execute_command(command);
    }

    fn render_command_palette(&self, rows: usize, cols: usize) {
        // Calculate palette dimensions (centered, 80% of screen)
        let palette_width = (cols * 80 / 100).max(40);
        let palette_height = (rows * 60 / 100).max(10);
        let start_x = (cols - palette_width) / 2;
        let start_y = (rows - palette_height) / 2;

        // Clear the palette area
        for y in start_y..start_y + palette_height {
            print_text_with_coordinates(
                Text::new(" ".repeat(palette_width)),
                start_x,
                y,
                Some(Color::Rgb(40, 40, 40)),
                Some(Color::Rgb(20, 20, 20))
            );
        }

        // Draw border
        let border_style = Style {
            colors: ColoredElements::new()
                .colored(ElementColor::Foreground, Color::Rgb(100, 100, 100))
                .colored(ElementColor::Background, Color::Rgb(20, 20, 20)),
        };

        // Title
        print_text_with_coordinates(
            Text::new("AI Command Palette").color_range(border_style, ..),
            start_x + 2,
            start_y + 1,
            None,
            None
        );

        // Search box
        let search_text = format!("Search: {}", self.search_query);
        print_text_with_coordinates(
            Text::new(search_text),
            start_x + 2,
            start_y + 3,
            Some(Color::Rgb(255, 255, 255)),
            Some(Color::Rgb(40, 40, 40))
        );

        // Commands list
        let visible_commands = palette_height.saturating_sub(6).min(self.commands.len());
        for (i, command) in self.commands.iter().take(visible_commands).enumerate() {
            let y = start_y + 5 + i;
            let is_selected = i == self.selected_command;
            
            let (fg_color, bg_color) = if is_selected {
                (Color::Rgb(0, 0, 0), Color::Rgb(100, 200, 255))
            } else {
                (Color::Rgb(200, 200, 200), Color::Rgb(30, 30, 30))
            };

            let category_indicator = match command.category {
                CommandCategory::Plan => "📋",
                CommandCategory::Edit => "✏️",
                CommandCategory::Review => "🔍",
                CommandCategory::Grunt => "🤖",
                CommandCategory::Context => "📄",
                CommandCategory::Model => "🧠",
            };

            let command_text = format!(
                "{} {} - {} [{}]",
                category_indicator,
                command.title,
                command.description,
                command.shortcut
            );

            print_text_with_coordinates(
                Text::new(command_text),
                start_x + 2,
                y,
                Some(fg_color),
                Some(bg_color)
            );
        }

        // Instructions at bottom
        let instructions = "↑↓: Navigate | Enter: Execute | Esc: Close | Type to search";
        print_text_with_coordinates(
            Text::new(instructions),
            start_x + 2,
            start_y + palette_height - 2,
            Some(Color::Rgb(150, 150, 150)),
            Some(Color::Rgb(20, 20, 20))
        );
    }

    fn render_status_bar(&self, _rows: usize, cols: usize) {
        // Render compact status information when palette is not visible
        let status_text = format!(
            "Mode: {} | Progress: {:.0}% | Tokens: {}/{} | Cost: ${:.4} | Ctrl+A: Commands",
            self.workflow_state.mode,
            self.workflow_state.progress * 100.0,
            self.workflow_state.token_usage.current,
            self.workflow_state.token_usage.total,
            self.workflow_state.token_usage.cost_usd
        );

        // Ensure text fits in available width
        let display_text = if status_text.len() > cols {
            format!("{}...", &status_text[..cols.saturating_sub(3)])
        } else {
            status_text
        };

        print_text_with_coordinates(
            Text::new(display_text),
            0,
            0,
            Some(Color::Rgb(200, 200, 200)),
            Some(Color::Rgb(40, 40, 50))
        );
    }
}