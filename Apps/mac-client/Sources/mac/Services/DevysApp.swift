// DevysApp.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import AppKit
import AppFeatures
import ComposableArchitecture
import Workspace

// App delegate to handle activation when running from a Swift Package.
// periphery:ignore - retained through @NSApplicationDelegateAdaptor runtime wiring
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var distributedAttentionObserver: NSObjectProtocol?
    var editorSessionRegistry: EditorSessionRegistry?
    var windowStore: StoreOf<WindowFeature>?

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
        let hasDirtyHostedEditors = windowStore?.withState { state in
            state.hostedWorkspaceContentByID.values.contains { $0.dirtyEditorCount > 0 }
        } ?? false
        guard hasDirtyHostedEditors else {
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
                let success = await (editorSessionRegistry?.saveAll() ?? true)
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
    // periphery:ignore - retained through @NSApplicationDelegateAdaptor runtime wiring
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var container: AppContainer
    @State private var appStore: StoreOf<AppFeature>

    init() {
        let container = AppContainer()
        _container = State(initialValue: container)
        _appStore = State(initialValue: AppFeaturesBootstrap.makeStore(container: container))
    }

    private var shortcutSettings: WorkspaceShellShortcutSettings {
        container.appSettings.shortcuts
    }
    
    var body: some Scene {
        WindowGroup {
            AppFeatureHost(store: appStore) {
                ContentView(store: appStore.scope(state: \.window, action: \.window))
                    .frame(minWidth: 900, minHeight: 600)
                    .onAppear {
                        appDelegate.editorSessionRegistry = container.editorSessionRegistry
                        appDelegate.windowStore = appStore.scope(state: \.window, action: \.window)
                    }
                    .environment(container)
                    .environment(container.appSettings)
                    .environment(container.recentRepositoriesService)
                    .environment(container.layoutPersistenceService)
                    .environment(container.repositorySettingsStore)
            }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Command Palette") {
                    appStore.send(.window(.openSearch(.commands, initialQuery: "")))
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
                    appStore.send(.window(.requestOpenRepository))
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .printItem) {
                Button("Open Quickly...") {
                    appStore.send(.window(.openSearch(.files, initialQuery: "")))
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            CommandMenu("Find") {
                Button("Find") {
                    appStore.send(.window(.requestEditorCommand(.find)))
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find In Files") {
                    appStore.send(.window(.openSearch(.textSearch, initialQuery: "")))
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandMenu("Sidebar") {
                Button("Show Files") {
                    appStore.send(.window(.showSidebar(.files)))
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Show Agents") {
                    appStore.send(.window(.showSidebar(.agents)))
                }
                .keyboardShortcut("2", modifiers: .command)

                Divider()

                Button("Toggle Sidebar") {
                    appStore.send(.window(.toggleSidebarVisibility))
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .toggleSidebar).keyboardShortcut
                )

                Button("Toggle Navigator") {
                    appStore.send(.window(.toggleNavigatorCollapsed))
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .toggleNavigator).keyboardShortcut
                )
            }

            CommandMenu("Workspace") {
                Button("Previous Workspace") {
                    appStore.send(.window(.requestAdjacentWorkspaceSelection(-1)))
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .previousWorkspace).keyboardShortcut
                )

                Button("Next Workspace") {
                    appStore.send(.window(.requestAdjacentWorkspaceSelection(1)))
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .nextWorkspace).keyboardShortcut
                )

                Divider()

                Button("Launch Shell") {
                    appStore.send(.window(.requestWorkspaceCommand(.launchShell)))
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .launchShell).keyboardShortcut
                )

                Button("Launch Claude") {
                    appStore.send(.window(.requestWorkspaceCommand(.launchClaude)))
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .launchClaude).keyboardShortcut
                )

                Button("Launch Codex") {
                    appStore.send(.window(.requestWorkspaceCommand(.launchCodex)))
                }
                .applyingKeyboardShortcut(
                    shortcutSettings.binding(for: .launchCodex).keyboardShortcut
                )

                Button("Run Default Profile") {
                    appStore.send(.window(.requestWorkspaceCommand(.runWorkspaceProfile)))
                }

                Divider()

                Button("Reveal Current Workspace in Navigator") {
                    appStore.send(.window(.revealCurrentWorkspaceInNavigator))
                }
            }

            CommandMenu("Workspaces") {
                Button("Select Workspace 1") {
                    appStore.send(.window(.requestWorkspaceSelectionAtIndex(0)))
                }
                .keyboardShortcut("1", modifiers: [.command, .control])

                Button("Select Workspace 2") {
                    appStore.send(.window(.requestWorkspaceSelectionAtIndex(1)))
                }
                .keyboardShortcut("2", modifiers: [.command, .control])

                Button("Select Workspace 3") {
                    appStore.send(.window(.requestWorkspaceSelectionAtIndex(2)))
                }
                .keyboardShortcut("3", modifiers: [.command, .control])

                Button("Select Workspace 4") {
                    appStore.send(.window(.requestWorkspaceSelectionAtIndex(3)))
                }
                .keyboardShortcut("4", modifiers: [.command, .control])

                Button("Select Workspace 5") {
                    appStore.send(.window(.requestWorkspaceSelectionAtIndex(4)))
                }
                .keyboardShortcut("5", modifiers: [.command, .control])

                Button("Select Workspace 6") {
                    appStore.send(.window(.requestWorkspaceSelectionAtIndex(5)))
                }
                .keyboardShortcut("6", modifiers: [.command, .control])

                Button("Select Workspace 7") {
                    appStore.send(.window(.requestWorkspaceSelectionAtIndex(6)))
                }
                .keyboardShortcut("7", modifiers: [.command, .control])

                Button("Select Workspace 8") {
                    appStore.send(.window(.requestWorkspaceSelectionAtIndex(7)))
                }
                .keyboardShortcut("8", modifiers: [.command, .control])

                Button("Select Workspace 9") {
                    appStore.send(.window(.requestWorkspaceSelectionAtIndex(8)))
                }
                .keyboardShortcut("9", modifiers: [.command, .control])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appStore.send(.window(.requestEditorCommand(.save)))
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As...") {
                    appStore.send(.window(.requestEditorCommand(.saveAs)))
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Save All") {
                    appStore.send(.window(.requestEditorCommand(.saveAll)))
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
            
            Group {
                CommandMenu("Layout") {
                    Button("Set Default Layout") {
                        appStore.send(.window(.requestSaveDefaultLayout))
                    }
                }

                CommandMenu("Notifications") {
                    Button("Jump to Latest Unread Workspace") {
                        appStore.send(.window(.requestWorkspaceCommand(.jumpToLatestUnreadWorkspace)))
                    }
                    .applyingKeyboardShortcut(
                        shortcutSettings.binding(for: .jumpToLatestUnreadWorkspace).keyboardShortcut
                    )

                    Button("Show Notifications") {
                        appStore.send(.window(.setNotificationsPanelPresented(true)))
                    }
                    .keyboardShortcut("n", modifiers: [.command, .control, .shift])
                }

                SidebarCommands()
            }
        }

        Settings {
            SettingsSceneRoot(store: appStore.scope(state: \.window, action: \.window))
                .environment(container.appSettings)
                .environment(container.repositorySettingsStore)
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
