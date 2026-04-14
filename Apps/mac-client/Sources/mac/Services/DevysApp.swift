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
    private var distributedAttentionObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activate the app and bring it to the foreground
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Default to dark mode for terminal aesthetic
        NSApp.appearance = NSAppearance(named: .darkAqua)

        distributedAttentionObserver = DistributedNotificationCenter.default()
            .addObserver(
                forName: .devysWorkspaceAttentionIngress,
                object: nil,
                queue: .main
            ) { notification in
                NotificationCenter.default.post(
                    name: .devysWorkspaceAttentionIngress,
                    object: nil,
                    userInfo: notification.userInfo
                )
            }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let distributedAttentionObserver {
            DistributedNotificationCenter.default().removeObserver(distributedAttentionObserver)
            self.distributedAttentionObserver = nil
        }
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

struct DevysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var container = AppContainer()

    private var shortcutSettings: WorkspaceShellShortcutSettings {
        container.appSettings.shortcuts
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(container)
                .environment(container.appSettings)
                .environment(container.recentRepositoriesService)
                .environment(container.layoutPersistenceService)
                .environment(container.repositorySettingsStore)
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Command Palette") {
                    NotificationCenter.default.post(name: .devysOpenCommandPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

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
                Button("Add Repository...") {
                    NotificationCenter.default.post(name: .devysAddRepository, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .printItem) {
                Button("Open Quickly...") {
                    NotificationCenter.default.post(name: .devysOpenFileSearch, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            CommandMenu("Find") {
                Button("Find") {
                    NotificationCenter.default.post(name: .devysShowEditorFind, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find In Files") {
                    NotificationCenter.default.post(name: .devysOpenTextSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandMenu("Sidebar") {
                Button("Show Files") {
                    NotificationCenter.default.post(name: .devysShowFilesSidebar, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Show Changes") {
                    NotificationCenter.default.post(name: .devysShowChangesSidebar, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Show Ports") {
                    NotificationCenter.default.post(name: .devysShowPortsSidebar, object: nil)
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .devysToggleSidebar, object: nil)
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .toggleSidebar).keyboardShortcut
                )

                Button("Toggle Navigator") {
                    NotificationCenter.default.post(name: .devysToggleNavigator, object: nil)
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .toggleNavigator).keyboardShortcut
                )
            }

            CommandMenu("Workspace") {
                Button("Previous Workspace") {
                    NotificationCenter.default.post(name: .devysSelectPreviousWorkspace, object: nil)
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .previousWorkspace).keyboardShortcut
                )

                Button("Next Workspace") {
                    NotificationCenter.default.post(name: .devysSelectNextWorkspace, object: nil)
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .nextWorkspace).keyboardShortcut
                )

                Divider()

                Button("Launch Shell") {
                    NotificationCenter.default.post(name: .devysLaunchShell, object: nil)
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .launchShell).keyboardShortcut
                )

                Button("Launch Claude") {
                    NotificationCenter.default.post(name: .devysLaunchClaude, object: nil)
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .launchClaude).keyboardShortcut
                )

                Button("Launch Codex") {
                    NotificationCenter.default.post(name: .devysLaunchCodex, object: nil)
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .launchCodex).keyboardShortcut
                )

                Button("Run Default Profile") {
                    NotificationCenter.default.post(name: .devysRunWorkspaceProfile, object: nil)
                }

                Divider()

                Button("Reveal Current Workspace in Navigator") {
                    NotificationCenter.default.post(
                        name: .devysRevealCurrentWorkspaceInNavigator,
                        object: nil
                    )
                }
            }

            CommandMenu("Workspaces") {
                Button("Select Workspace 1") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorkspaceIndex,
                        object: nil,
                        userInfo: ["index": 0]
                    )
                }
                .keyboardShortcut("1", modifiers: [.command, .control])

                Button("Select Workspace 2") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorkspaceIndex,
                        object: nil,
                        userInfo: ["index": 1]
                    )
                }
                .keyboardShortcut("2", modifiers: [.command, .control])

                Button("Select Workspace 3") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorkspaceIndex,
                        object: nil,
                        userInfo: ["index": 2]
                    )
                }
                .keyboardShortcut("3", modifiers: [.command, .control])

                Button("Select Workspace 4") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorkspaceIndex,
                        object: nil,
                        userInfo: ["index": 3]
                    )
                }
                .keyboardShortcut("4", modifiers: [.command, .control])

                Button("Select Workspace 5") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorkspaceIndex,
                        object: nil,
                        userInfo: ["index": 4]
                    )
                }
                .keyboardShortcut("5", modifiers: [.command, .control])

                Button("Select Workspace 6") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorkspaceIndex,
                        object: nil,
                        userInfo: ["index": 5]
                    )
                }
                .keyboardShortcut("6", modifiers: [.command, .control])

                Button("Select Workspace 7") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorkspaceIndex,
                        object: nil,
                        userInfo: ["index": 6]
                    )
                }
                .keyboardShortcut("7", modifiers: [.command, .control])

                Button("Select Workspace 8") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorkspaceIndex,
                        object: nil,
                        userInfo: ["index": 7]
                    )
                }
                .keyboardShortcut("8", modifiers: [.command, .control])

                Button("Select Workspace 9") {
                    NotificationCenter.default.post(
                        name: .devysSelectWorkspaceIndex,
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
            
            Group {
                CommandMenu("Layout") {
                    Button("Set Default Layout") {
                        NotificationCenter.default.post(name: .devysSaveDefaultLayout, object: nil)
                    }
                }

                CommandMenu("Notifications") {
                    Button("Jump to Latest Unread Workspace") {
                        NotificationCenter.default.post(
                            name: .devysJumpToLatestUnreadWorkspace,
                            object: nil
                        )
                    }
                    .applyingKeyboardShortcut(
                        shortcutSettings.binding(for: .jumpToLatestUnreadWorkspace).keyboardShortcut
                    )

                    Button("Show Notifications") {
                        NotificationCenter.default.post(
                            name: .devysShowWorkspaceNotifications,
                            object: nil
                        )
                    }
                    .keyboardShortcut("n", modifiers: [.command, .control, .shift])
                }

                SidebarCommands()
            }
        }
    }
}

@main
enum DevysMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--workspace-notify") {
            do {
                try handleWorkspaceNotification(arguments: arguments)
                exit(0)
            } catch {
                fputs("workspace notify failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        if arguments.contains("--workspace-notify-hook") {
            do {
                try handleWorkspaceHookNotification(arguments: arguments)
                exit(0)
            } catch {
                fputs("workspace notify hook failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        if let socketIndex = arguments.firstIndex(of: "--terminal-host"),
           socketIndex + 2 < arguments.count,
           arguments[socketIndex + 1] == "--socket" {
            let socketPath = arguments[socketIndex + 2]
            do {
                try PersistentTerminalHostDaemon(socketPath: socketPath).run()
            } catch {
                fputs("terminal host failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        if arguments.contains("--terminal-attach") {
            PersistentTerminalAttachMain.run(arguments: arguments)
        }

        DevysApp.main()
    }

    private static func handleWorkspaceNotification(arguments: [String]) throws {
        let workspaceID = argumentValue("--workspace-id", in: arguments)
            ?? ProcessInfo.processInfo.environment["DEVYS_WORKSPACE_ID"]
        let terminalID = argumentValue("--terminal-id", in: arguments)
            ?? ProcessInfo.processInfo.environment["DEVYS_TERMINAL_ID"]
        let payload = try WorkspaceAttentionIngress.makePayload(
            workspaceID: workspaceID,
            terminalID: terminalID,
            source: try requiredArgumentValue("--source", in: arguments),
            kind: try requiredArgumentValue("--kind", in: arguments),
            title: try requiredArgumentValue("--title", in: arguments),
            subtitle: argumentValue("--subtitle", in: arguments)
        )
        try postWorkspaceAttention(payload)
    }

    private static func handleWorkspaceHookNotification(arguments: [String]) throws {
        let source = try requiredArgumentValue("--source", in: arguments)
        let kind = try requiredArgumentValue("--kind", in: arguments)
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        let workspaceID = argumentValue("--workspace-id", in: arguments)
            ?? ProcessInfo.processInfo.environment["DEVYS_WORKSPACE_ID"]
        let terminalID = argumentValue("--terminal-id", in: arguments)
            ?? ProcessInfo.processInfo.environment["DEVYS_TERMINAL_ID"]
        let payload = try WorkspaceAttentionIngress.makePayload(
            fromHookInput: stdinData,
            workspaceID: workspaceID,
            terminalID: terminalID,
            source: source,
            kind: kind
        )
        try postWorkspaceAttention(payload)
    }

    private static func postWorkspaceAttention(
        _ payload: WorkspaceAttentionIngressPayload
    ) throws {
        let encodedPayload = try WorkspaceAttentionIngress.encode(payload)
        DistributedNotificationCenter.default().postNotificationName(
            .devysWorkspaceAttentionIngress,
            object: nil,
            userInfo: [WorkspaceAttentionIngress.userInfoPayloadKey: encodedPayload],
            options: [.deliverImmediately]
        )
    }

    private static func argumentValue(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count
        else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func requiredArgumentValue(
        _ flag: String,
        in arguments: [String]
    ) throws -> String {
        guard let value = argumentValue(flag, in: arguments) else {
            throw NSError(
                domain: "DevysMain",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing required argument \(flag)."]
            )
        }
        return value
    }
}
