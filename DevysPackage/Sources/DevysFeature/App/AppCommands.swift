import SwiftUI

/// Menu bar commands for the Devys application.
///
/// Provides commands for:
/// - File operations (New, Open, Save)
/// - View operations (Zoom)
/// - Pane creation
public struct AppCommands: Commands {
    public init() {}

    public var body: some Commands {
        // MARK: - File Menu Additions

        CommandGroup(after: .newItem) {
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
                    // TODO: Implement in Sprint 2
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    // TODO: Implement in Sprint 2
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Zoom to Fit") {
                    // TODO: Implement in Sprint 2
                    NotificationCenter.default.post(name: .zoomToFit, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Button("Zoom to 100%") {
                    // TODO: Implement in Sprint 2
                    NotificationCenter.default.post(name: .zoomTo100, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)
            }
        }

        // MARK: - Pane Menu

        CommandMenu("Pane") {
            Section {
                Button("New Terminal") {
                    // TODO: Implement in Sprint 7
                    NotificationCenter.default.post(name: .newTerminal, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("New Browser") {
                    // TODO: Implement in Sprint 8
                    NotificationCenter.default.post(name: .newBrowser, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("New File Explorer") {
                    // TODO: Implement in Sprint 9
                    NotificationCenter.default.post(name: .newFileExplorer, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("New Code Editor") {
                    // TODO: Implement in Sprint 9
                    NotificationCenter.default.post(name: .newCodeEditor, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Button("New Git") {
                    // TODO: Implement in Sprint 10
                    NotificationCenter.default.post(name: .newGit, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }

            Divider()

            Section {
                Button("Toggle Fullscreen") {
                    // TODO: Implement in Sprint 4
                    NotificationCenter.default.post(name: .togglePaneFullscreen, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Duplicate Pane") {
                    // TODO: Implement in Sprint 4
                    NotificationCenter.default.post(name: .duplicatePane, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Close Pane") {
                    // TODO: Implement in Sprint 4
                    NotificationCenter.default.post(name: .closePane, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            Divider()

            Section {
                Button("Group Selected") {
                    // TODO: Implement in Sprint 5
                    NotificationCenter.default.post(name: .groupPanes, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Ungroup") {
                    // TODO: Implement in Sprint 5
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
