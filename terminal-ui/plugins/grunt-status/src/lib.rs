use zellij_tile::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use chrono::{DateTime, Utc, Duration};

#[derive(Default, Debug)]
struct GruntStatusPlugin {
    task_queue: Vec<GruntTask>,
    active_models: HashMap<String, ModelStatus>,
    cost_tracker: CostTracker,
    last_update: Option<DateTime<Utc>>,
    scroll_offset: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct GruntTask {
    id: String,
    task_type: GruntTaskType,
    status: TaskStatus,
    model: String,
    files: Vec<String>,
    started_at: DateTime<Utc>,
    completed_at: Option<DateTime<Utc>>,
    progress: f32,
    error_message: Option<String>,
    tokens_used: usize,
    estimated_cost: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
enum GruntTaskType {
    Format,
    Lint,
    Test,
    Commit,
    Documentation,
    CodeReview,
    Refactor,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
enum TaskStatus {
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ModelStatus {
    name: String,
    provider: String,
    is_local: bool,
    is_available: bool,
    current_task_id: Option<String>,
    queue_length: usize,
    tokens_per_minute: f32,
    cost_per_token: f32,
    last_response_time: Option<Duration>,
}

#[derive(Debug, Default)]
struct CostTracker {
    daily_cost: f32,
    monthly_cost: f32,
    total_tokens: usize,
    cost_by_model: HashMap<String, f32>,
    daily_limit: f32,
}

register_plugin!(GruntStatusPlugin);

impl ZellijPlugin for GruntStatusPlugin {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        // Load configuration
        if let Some(daily_limit) = configuration.get("daily_limit") {
            if let Ok(limit) = daily_limit.parse::<f32>() {
                self.cost_tracker.daily_limit = limit;
            }
        }

        // Initialize with some sample data (in real implementation, this would come from WebSocket)
        self.initialize_sample_data();

        // Subscribe to events
        subscribe(&[EventType::Key, EventType::Timer]);
        
        // Start update timer (refresh every 1 second)
        set_timeout(1.0);

        // Request permissions
        request_permission(&[PermissionType::ReadApplicationState]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::Key(key) => {
                match key {
                    Key::Up => {
                        if self.scroll_offset > 0 {
                            self.scroll_offset -= 1;
                        }
                        true
                    }
                    Key::Down => {
                        self.scroll_offset += 1;
                        true
                    }
                    Key::Char('r') => {
                        // Refresh data
                        self.request_data_refresh();
                        true
                    }
                    Key::Char('c') => {
                        // Clear completed tasks
                        self.task_queue.retain(|task| {
                            !matches!(task.status, TaskStatus::Completed)
                        });
                        true
                    }
                    Key::Char('k') => {
                        // Kill selected task (if running)
                        self.kill_selected_task();
                        true
                    }
                    _ => false
                }
            }
            Event::Timer(_) => {
                // Update progress for running tasks
                self.update_task_progress();
                // Reset timer
                set_timeout(1.0);
                true
            }
            Event::CustomMessage(message) => {
                // Handle updates from Control Plane
                self.handle_control_plane_message(&message.payload);
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
                Some(Color::Rgb(20, 25, 30))
            );
        }

        let mut current_row = 0;

        // Header
        current_row += self.render_header(current_row, cols);
        current_row += 1; // Separator

        // Cost tracker
        current_row += self.render_cost_tracker(current_row, cols);
        current_row += 1; // Separator

        // Active models status
        current_row += self.render_models_status(current_row, cols, rows - current_row - 3);
        current_row += 1; // Separator

        // Task queue
        self.render_task_queue(current_row, cols, rows - current_row - 1);

        // Footer with controls
        self.render_footer(rows - 1, cols);
    }
}

impl GruntStatusPlugin {
    fn initialize_sample_data(&mut self) {
        // Initialize sample models (would be loaded from control plane)
        self.active_models.insert("ollama:qwen2.5-coder:14b".to_string(), ModelStatus {
            name: "qwen2.5-coder:14b".to_string(),
            provider: "ollama".to_string(),
            is_local: true,
            is_available: true,
            current_task_id: Some("task_001".to_string()),
            queue_length: 2,
            tokens_per_minute: 1500.0,
            cost_per_token: 0.0,
            last_response_time: Some(Duration::milliseconds(250)),
        });

        self.active_models.insert("deepseek-chat".to_string(), ModelStatus {
            name: "deepseek-chat".to_string(),
            provider: "deepseek".to_string(),
            is_local: false,
            is_available: true,
            current_task_id: None,
            queue_length: 0,
            tokens_per_minute: 3000.0,
            cost_per_token: 0.0001,
            last_response_time: Some(Duration::milliseconds(800)),
        });

        // Initialize sample tasks
        let now = Utc::now();
        self.task_queue.push(GruntTask {
            id: "task_001".to_string(),
            task_type: GruntTaskType::Format,
            status: TaskStatus::Running,
            model: "ollama:qwen2.5-coder:14b".to_string(),
            files: vec!["src/main.rs".to_string(), "src/lib.rs".to_string()],
            started_at: now - Duration::seconds(15),
            completed_at: None,
            progress: 0.65,
            error_message: None,
            tokens_used: 1250,
            estimated_cost: 0.0,
        });

        self.task_queue.push(GruntTask {
            id: "task_002".to_string(),
            task_type: GruntTaskType::Test,
            status: TaskStatus::Queued,
            model: "ollama:qwen2.5-coder:14b".to_string(),
            files: vec!["tests/".to_string()],
            started_at: now,
            completed_at: None,
            progress: 0.0,
            error_message: None,
            tokens_used: 0,
            estimated_cost: 0.0,
        });

        // Initialize cost tracker
        self.cost_tracker.daily_cost = 2.45;
        self.cost_tracker.monthly_cost = 67.80;
        self.cost_tracker.total_tokens = 245600;
        self.cost_tracker.daily_limit = 5.00;
    }

    fn render_header(&self, row: usize, cols: usize) -> usize {
        let title = "Grunt Status - AI Background Tasks";
        let timestamp = Utc::now().format("%H:%M:%S").to_string();
        let header_text = format!("{:width$} {}", title, timestamp, width = cols.saturating_sub(timestamp.len() + 1));

        print_text_with_coordinates(
            Text::new(header_text),
            0,
            row,
            Some(Color::Rgb(100, 200, 255)),
            Some(Color::Rgb(30, 30, 40))
        );

        1
    }

    fn render_cost_tracker(&self, row: usize, cols: usize) -> usize {
        let daily_percentage = (self.cost_tracker.daily_cost / self.cost_tracker.daily_limit * 100.0) as u16;
        let cost_text = format!(
            "💰 Daily: ${:.2}/{:.2} ({}%) | Monthly: ${:.2} | Tokens: {}k",
            self.cost_tracker.daily_cost,
            self.cost_tracker.daily_limit,
            daily_percentage,
            self.cost_tracker.monthly_cost,
            self.cost_tracker.total_tokens / 1000
        );

        let cost_color = match daily_percentage {
            0..=50 => Color::Rgb(0, 255, 0),   // Green
            51..=80 => Color::Rgb(255, 255, 0), // Yellow  
            _ => Color::Rgb(255, 0, 0),         // Red
        };

        print_text_with_coordinates(
            Text::new(cost_text),
            0,
            row,
            Some(cost_color),
            Some(Color::Rgb(25, 25, 25))
        );

        // Progress bar for daily cost
        let bar_width = cols.min(60);
        let filled_width = (bar_width * daily_percentage as usize / 100).min(bar_width);
        let bar_text = format!(
            "[{}{}]",
            "█".repeat(filled_width),
            "░".repeat(bar_width - filled_width)
        );

        print_text_with_coordinates(
            Text::new(bar_text),
            0,
            row + 1,
            Some(cost_color),
            Some(Color::Rgb(25, 25, 25))
        );

        2
    }

    fn render_models_status(&self, start_row: usize, cols: usize, max_rows: usize) -> usize {
        let header = "Active Models:";
        print_text_with_coordinates(
            Text::new(header),
            0,
            start_row,
            Some(Color::Rgb(200, 200, 200)),
            Some(Color::Rgb(25, 25, 25))
        );

        let mut row = start_row + 1;
        let available_rows = max_rows.saturating_sub(1);

        for (i, (model_id, status)) in self.active_models.iter().enumerate() {
            if i >= available_rows {
                break;
            }

            let indicator = if status.is_available {
                if status.current_task_id.is_some() { "🟡" } else { "🟢" }
            } else {
                "🔴"
            };

            let location = if status.is_local { "LOCAL" } else { "REMOTE" };
            let queue_info = if status.queue_length > 0 {
                format!(" (Queue: {})", status.queue_length)
            } else {
                String::new()
            };

            let response_time = status.last_response_time
                .map(|d| format!("{}ms", d.num_milliseconds()))
                .unwrap_or_else(|| "N/A".to_string());

            let model_text = format!(
                "{} {} [{}] - {:.0} tok/min - {} - {}{}",
                indicator,
                status.name,
                location,
                status.tokens_per_minute,
                response_time,
                if status.cost_per_token > 0.0 { format!("${:.6}/tok", status.cost_per_token) } else { "FREE".to_string() },
                queue_info
            );

            let color = if status.is_available {
                if status.current_task_id.is_some() {
                    Color::Rgb(255, 255, 0)  // Yellow for busy
                } else {
                    Color::Rgb(0, 255, 0)    // Green for available
                }
            } else {
                Color::Rgb(255, 0, 0)        // Red for unavailable
            };

            print_text_with_coordinates(
                Text::new(model_text),
                2,
                row,
                Some(color),
                Some(Color::Rgb(25, 25, 25))
            );

            row += 1;
        }

        row - start_row
    }

    fn render_task_queue(&self, start_row: usize, cols: usize, max_rows: usize) {
        let header = "Task Queue:";
        print_text_with_coordinates(
            Text::new(header),
            0,
            start_row,
            Some(Color::Rgb(200, 200, 200)),
            Some(Color::Rgb(25, 25, 25))
        );

        let mut row = start_row + 1;
        let available_rows = max_rows.saturating_sub(1);

        let visible_tasks: Vec<_> = self.task_queue
            .iter()
            .skip(self.scroll_offset)
            .take(available_rows)
            .collect();

        for task in visible_tasks {
            let status_indicator = match task.status {
                TaskStatus::Queued => "⏳",
                TaskStatus::Running => "🔄",
                TaskStatus::Completed => "✅",
                TaskStatus::Failed => "❌",
                TaskStatus::Cancelled => "⏹️",
            };

            let task_type_str = match task.task_type {
                GruntTaskType::Format => "FMT",
                GruntTaskType::Lint => "LINT",
                GruntTaskType::Test => "TEST",
                GruntTaskType::Commit => "COMMIT",
                GruntTaskType::Documentation => "DOCS",
                GruntTaskType::CodeReview => "REVIEW",
                GruntTaskType::Refactor => "REFACTOR",
            };

            let duration = if let Some(completed_at) = task.completed_at {
                let duration = completed_at - task.started_at;
                format!("{}s", duration.num_seconds())
            } else {
                let duration = Utc::now() - task.started_at;
                format!("{}s", duration.num_seconds())
            };

            let progress_bar = if matches!(task.status, TaskStatus::Running) {
                let filled = ((task.progress * 20.0) as usize).min(20);
                format!("[{}{}]", "█".repeat(filled), "░".repeat(20 - filled))
            } else {
                String::new()
            };

            let files_summary = if task.files.len() > 2 {
                format!("{} files", task.files.len())
            } else {
                task.files.join(", ")
            };

            let task_text = format!(
                "{} {} {} {} | {} | {} | {}tok {}",
                status_indicator,
                task_type_str,
                task.model.split(':').last().unwrap_or(&task.model),
                progress_bar,
                files_summary,
                duration,
                task.tokens_used,
                if task.estimated_cost > 0.0 { format!("${:.4}", task.estimated_cost) } else { "FREE".to_string() }
            );

            let color = match task.status {
                TaskStatus::Running => Color::Rgb(255, 255, 0),
                TaskStatus::Completed => Color::Rgb(0, 255, 0),
                TaskStatus::Failed => Color::Rgb(255, 0, 0),
                TaskStatus::Cancelled => Color::Rgb(128, 128, 128),
                TaskStatus::Queued => Color::Rgb(200, 200, 200),
            };

            print_text_with_coordinates(
                Text::new(task_text),
                2,
                row,
                Some(color),
                Some(Color::Rgb(25, 25, 25))
            );

            if let Some(error) = &task.error_message {
                print_text_with_coordinates(
                    Text::new(format!("    Error: {}", error)),
                    2,
                    row + 1,
                    Some(Color::Rgb(255, 100, 100)),
                    Some(Color::Rgb(25, 25, 25))
                );
                row += 1;
            }

            row += 1;
        }
    }

    fn render_footer(&self, row: usize, cols: usize) {
        let controls = "↑↓: Scroll | r: Refresh | c: Clear completed | k: Kill task | Ctrl+C: Exit";
        let footer_text = if controls.len() > cols {
            format!("{}...", &controls[..cols.saturating_sub(3)])
        } else {
            controls.to_string()
        };

        print_text_with_coordinates(
            Text::new(footer_text),
            0,
            row,
            Some(Color::Rgb(150, 150, 150)),
            Some(Color::Rgb(40, 40, 50))
        );
    }

    fn update_task_progress(&mut self) {
        for task in &mut self.task_queue {
            if matches!(task.status, TaskStatus::Running) {
                // Simulate progress updates (in real implementation, this comes from WebSocket)
                task.progress = (task.progress + 0.05).min(1.0);
                
                if task.progress >= 1.0 {
                    task.status = TaskStatus::Completed;
                    task.completed_at = Some(Utc::now());
                    
                    // Free up the model
                    if let Some(model) = self.active_models.get_mut(&task.model) {
                        model.current_task_id = None;
                        if model.queue_length > 0 {
                            model.queue_length -= 1;
                        }
                    }
                }
            }
        }
    }

    fn request_data_refresh(&mut self) {
        post_message_to("control-plane", "grunt:status-refresh".to_string());
    }

    fn kill_selected_task(&mut self) {
        // Find first running task and cancel it
        for task in &mut self.task_queue {
            if matches!(task.status, TaskStatus::Running) {
                task.status = TaskStatus::Cancelled;
                task.completed_at = Some(Utc::now());
                
                post_message_to("control-plane", 
                    format!("grunt:kill-task:{}", task.id)
                );
                break;
            }
        }
    }

    fn handle_control_plane_message(&mut self, payload: &str) {
        if let Ok(update) = serde_json::from_str::<GruntStatusUpdate>(payload) {
            match update {
                GruntStatusUpdate::NewTask(task) => {
                    self.task_queue.push(task);
                }
                GruntStatusUpdate::TaskUpdate(task_id, status, progress) => {
                    if let Some(task) = self.task_queue.iter_mut().find(|t| t.id == task_id) {
                        task.status = status;
                        task.progress = progress;
                    }
                }
                GruntStatusUpdate::ModelStatus(model_id, status) => {
                    self.active_models.insert(model_id, status);
                }
                GruntStatusUpdate::CostUpdate(cost_tracker) => {
                    self.cost_tracker = cost_tracker;
                }
            }
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
enum GruntStatusUpdate {
    NewTask(GruntTask),
    TaskUpdate(String, TaskStatus, f32), // id, status, progress
    ModelStatus(String, ModelStatus),     // model_id, status
    CostUpdate(CostTracker),
}