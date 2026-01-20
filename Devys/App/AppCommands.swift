import SwiftUI

/// Menu bar commands for the Devys application.
///
/// Provides commands for:
/// - File operations (New, Open, Save)
/// - View operations (Zoom)
/// - Tab management
/// - Pane creation
public struct AppCommands: Commands {
    public init() {}

    public var body: some Commands {
        // MARK: - File Menu Additions

        CommandGroup(after: .newItem) {
            Button("Open Project...") {
                NotificationCenter.default.post(name: .showOpenProjectDialog, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("New Tab") {
                NotificationCenter.default.post(name: .newTab, object: nil)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                NotificationCenter.default.post(name: .closeTab, object: nil)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Divider()

            Button("New Canvas") {
                // TODO: Implement in Sprint 10 (Persistence)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        // MARK: - View Menu

        CommandGroup(after: .toolbar) {
            Section {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Zoom to Fit") {
                    NotificationCenter.default.post(name: .zoomToFit, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Button("Zoom to 100%") {
                    NotificationCenter.default.post(name: .zoomTo100, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)
            }

            Divider()

            Section {
                Button("Show Next Tab") {
                    NotificationCenter.default.post(name: .nextTab, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Show Previous Tab") {
                    NotificationCenter.default.post(name: .previousTab, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            }

            Divider()

            // Pane focus commands (⌘2-9, ⌘1 is reserved for Zoom to 100%)
            Section {
                ForEach(2...9, id: \.self) { index in
                    Button("Focus Pane \(index)") {
                        NotificationCenter.default.post(name: .focusPaneByHotkey, object: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                }
            }
        }

        // MARK: - Pane Menu

        CommandMenu("Pane") {
            Section {
                Button("New Terminal") {
                    NotificationCenter.default.post(name: .newTerminal, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("New Browser") {
                    NotificationCenter.default.post(name: .newBrowser, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("New File Explorer") {
                    NotificationCenter.default.post(name: .newFileExplorer, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("New Code Editor") {
                    NotificationCenter.default.post(name: .newCodeEditor, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Button("New Git") {
                    NotificationCenter.default.post(name: .newGit, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }

            Divider()

            Section {
                Button("Toggle Fullscreen") {
                    NotificationCenter.default.post(name: .togglePaneFullscreen, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Duplicate Pane") {
                    NotificationCenter.default.post(name: .duplicatePane, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Close Pane") {
                    NotificationCenter.default.post(name: .closePane, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            Divider()

            Section {
                Button("Group Selected") {
                    NotificationCenter.default.post(name: .groupPanes, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Ungroup") {
                    NotificationCenter.default.post(name: .ungroupPanes, object: nil)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    // View
    static let zoomIn = Notification.Name("devys.zoomIn")
    static let zoomOut = Notification.Name("devys.zoomOut")
    static let zoomToFit = Notification.Name("devys.zoomToFit")
    static let zoomTo100 = Notification.Name("devys.zoomTo100")

    // Tabs
    static let newTab = Notification.Name("devys.newTab")
    static let closeTab = Notification.Name("devys.closeTab")
    static let nextTab = Notification.Name("devys.nextTab")
    static let previousTab = Notification.Name("devys.previousTab")

    // Pane Creation
    static let newTerminal = Notification.Name("devys.newTerminal")
    static let newBrowser = Notification.Name("devys.newBrowser")
    static let newFileExplorer = Notification.Name("devys.newFileExplorer")
    static let newCodeEditor = Notification.Name("devys.newCodeEditor")
    static let newGit = Notification.Name("devys.newGit")

    // Pane Actions
    static let togglePaneFullscreen = Notification.Name("devys.togglePaneFullscreen")
    static let duplicatePane = Notification.Name("devys.duplicatePane")
    static let closePane = Notification.Name("devys.closePane")

    // Grouping
    static let groupPanes = Notification.Name("devys.groupPanes")
    static let ungroupPanes = Notification.Name("devys.ungroupPanes")
}
