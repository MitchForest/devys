//
//  devysApp.swift
//  devys
//
//  An agent-native IDE for macOS.
//  Orchestrate Codex and Claude Code with a beautiful native interface.
//

import SwiftUI
import SwiftData

@main
struct DevysApp: App {
    // MARK: - State
    
    @AppStorage("appearance") private var appearance: Appearance = .system
    
    // MARK: - Services
    
    /// Process manager for CLI processes.
    @State private var processManager = ProcessManager()
    
    // MARK: - SwiftData
    
    /// Only Workspace is persisted. Everything else is runtime.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Workspace.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(processManager)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Workspace...") {
                    NotificationCenter.default.post(name: .addWorkspace, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            
            CommandGroup(after: .toolbar) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
        }
        
        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

// MARK: - Appearance

enum Appearance: String, CaseIterable {
    case system
    case light
    case dark
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}
