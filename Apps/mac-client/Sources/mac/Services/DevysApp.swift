// DevysApp.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import AppKit
import Workspace

/// App delegate to handle activation when running from a Swift Package
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activate the app and bring it to the foreground
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Default to dark mode for terminal aesthetic
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirtySessions = EditorSessionRegistry.shared.dirtySessions
        guard !dirtySessions.isEmpty else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes before quitting?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                let success = await EditorSessionRegistry.shared.saveAll()
                if success {
                    sender.reply(toApplicationShouldTerminate: true)
                } else {
                    let errorAlert = NSAlert()
                    errorAlert.alertStyle = .critical
                    errorAlert.messageText = "Save failed"
                    errorAlert.informativeText = "One or more files could not be saved."
                    errorAlert.addButton(withTitle: "OK")
                    errorAlert.runModal()
                    sender.reply(toApplicationShouldTerminate: false)
                }
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}

@main
struct DevysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var container = AppContainer()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(container)
                .environment(container.appSettings)
                .environment(container.recentFoldersService)
                .environment(container.layoutPersistenceService)
                .environment(container.commandSettingsStore)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    // TODO: Implement new tab
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("New Window") {
                    // TODO: Implement new window
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Open Folder...") {
                    NotificationCenter.default.post(name: .devysOpenFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Show Explorer") {
                    NotificationCenter.default.post(name: .devysShowExplorer, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Show Git") {
                    NotificationCenter.default.post(name: .devysShowGit, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Show Worktrees") {
                    NotificationCenter.default.post(name: .devysShowWorktrees, object: nil)
                }
                .keyboardShortcut("3", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("Select Worktree 1") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorktreeIndex,
                        object: nil,
                        userInfo: ["index": 0]
                    )
                }
                .keyboardShortcut("1", modifiers: [.command, .control])

                Button("Select Worktree 2") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorktreeIndex,
                        object: nil,
                        userInfo: ["index": 1]
                    )
                }
                .keyboardShortcut("2", modifiers: [.command, .control])

                Button("Select Worktree 3") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorktreeIndex,
                        object: nil,
                        userInfo: ["index": 2]
                    )
                }
                .keyboardShortcut("3", modifiers: [.command, .control])

                Button("Select Worktree 4") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorktreeIndex,
                        object: nil,
                        userInfo: ["index": 3]
                    )
                }
                .keyboardShortcut("4", modifiers: [.command, .control])

                Button("Select Worktree 5") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorktreeIndex,
                        object: nil,
                        userInfo: ["index": 4]
                    )
                }
                .keyboardShortcut("5", modifiers: [.command, .control])

                Button("Select Worktree 6") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorktreeIndex,
                        object: nil,
                        userInfo: ["index": 5]
                    )
                }
                .keyboardShortcut("6", modifiers: [.command, .control])

                Button("Select Worktree 7") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorktreeIndex,
                        object: nil,
                        userInfo: ["index": 6]
                    )
                }
                .keyboardShortcut("7", modifiers: [.command, .control])

                Button("Select Worktree 8") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorktreeIndex,
                        object: nil,
                        userInfo: ["index": 7]
                    )
                }
                .keyboardShortcut("8", modifiers: [.command, .control])

                Button("Select Worktree 9") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorktreeIndex,
                        object: nil,
                        userInfo: ["index": 8]
                    )
                }
                .keyboardShortcut("9", modifiers: [.command, .control])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .devysSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As...") {
                    NotificationCenter.default.post(name: .devysSaveAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Save All") {
                    NotificationCenter.default.post(name: .devysSaveAll, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
            
            CommandMenu("Layout") {
                Button("Set Default Layout") {
                    NotificationCenter.default.post(name: .devysSaveDefaultLayout, object: nil)
                }
            }
            
            SidebarCommands()
        }
    }
}
