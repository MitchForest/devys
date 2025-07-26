use tauri::{Manager, menu::{Menu, MenuBuilder, MenuItemBuilder, SubmenuBuilder}};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let handle = app.handle();
            let menu = create_app_menu(&handle)?;
            app.set_menu(menu)?;
            
            #[cfg(debug_assertions)]
            {
                let window = app.get_webview_window("main").unwrap();
                window.open_devtools();
            }
            Ok(())
        })
        .on_menu_event(|app, event| {
            let window = app.get_webview_window("main").unwrap();
            match event.id().as_ref() {
                "new_terminal" => {
                    window.emit("menu-action", "new-terminal").unwrap();
                }
                "close_terminal" => {
                    window.emit("menu-action", "close-terminal").unwrap();
                }
                "open_folder" => {
                    window.emit("menu-action", "open-folder").unwrap();
                }
                "toggle_chat" => {
                    window.emit("menu-action", "toggle-chat").unwrap();
                }
                _ => {}
            }
        })
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn create_app_menu(handle: &tauri::AppHandle) -> Result<Menu<tauri::Wry>, Box<dyn std::error::Error>> {
    let mut menu = MenuBuilder::new(handle);
    
    // macOS app menu
    #[cfg(target_os = "macos")]
    {
        let app_menu = SubmenuBuilder::new(handle, "Devys")
            .about()
            .separator()
            .services()
            .separator()
            .hide()
            .hide_others()
            .show_all()
            .separator()
            .quit()
            .build()?;
        
        menu = menu.item(&app_menu);
    }
    
    // File menu
    let open_folder = MenuItemBuilder::new("Open Folder...")
        .id("open_folder")
        .accelerator("CmdOrCtrl+O")
        .build(handle)?;
    
    let file_menu = SubmenuBuilder::new(handle, "File")
        .item(&open_folder)
        .separator()
        .close_window()
        .build()?;
    
    // Edit menu
    let edit_menu = SubmenuBuilder::new(handle, "Edit")
        .undo()
        .redo()
        .separator()
        .cut()
        .copy()
        .paste()
        .select_all()
        .build()?;
    
    // View menu
    let toggle_chat = MenuItemBuilder::new("Toggle Chat")
        .id("toggle_chat")
        .accelerator("CmdOrCtrl+Shift+C")
        .build(handle)?;
    
    let view_menu = SubmenuBuilder::new(handle, "View")
        .item(&toggle_chat)
        .separator()
        .fullscreen()
        .build()?;
    
    // Terminal menu
    let new_terminal = MenuItemBuilder::new("New Terminal")
        .id("new_terminal")
        .accelerator("CmdOrCtrl+T")
        .build(handle)?;
    
    let close_terminal = MenuItemBuilder::new("Close Terminal")
        .id("close_terminal")
        .accelerator("CmdOrCtrl+W")
        .build(handle)?;
    
    let terminal_menu = SubmenuBuilder::new(handle, "Terminal")
        .item(&new_terminal)
        .item(&close_terminal)
        .build()?;
    
    // Window menu
    let window_menu = SubmenuBuilder::new(handle, "Window")
        .minimize()
        .zoom()
        .build()?;
    
    menu = menu
        .item(&file_menu)
        .item(&edit_menu)
        .item(&view_menu)
        .item(&terminal_menu)
        .item(&window_menu);
    
    Ok(menu.build()?)
}