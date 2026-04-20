import Foundation
import Observation

public enum GhosttyTerminalStartupPhase: String, Equatable, Sendable {
    case startingHost
    case awaitingViewport
    case startingShell
    case ready
    case failed
}

@MainActor
@Observable
public final class GhosttyTerminalSession: Identifiable {
    public let id: UUID
    public var tabTitle: String
    public let tabIcon: String
    public var bellCount: Int
    public var isRunning: Bool
    public var focusRequestID: Int
    public var workingDirectory: URL?
    public var requestedCommand: String?
    public var stagedCommand: String?
    public var terminateHostedSessionOnClose: Bool
    public var currentDirectory: URL?
    public var lastErrorDescription: String?
    public var startupPhase: GhosttyTerminalStartupPhase

    @ObservationIgnored
    var shutdownHandler: (@MainActor () -> Void)?

    @ObservationIgnored
    var focusRequestHandler: (@MainActor (Int) -> Void)?

    public init(
        id: UUID = UUID(),
        workingDirectory: URL? = nil,
        requestedCommand: String? = nil,
        stagedCommand: String? = nil,
        tabIcon: String = "terminal",
        terminateHostedSessionOnClose: Bool = true,
        startupPhase: GhosttyTerminalStartupPhase = .startingShell
    ) {
        self.id = id
        self.tabTitle = "Terminal"
        self.tabIcon = tabIcon
        self.bellCount = 0
        self.isRunning = true
        self.focusRequestID = 0
        self.workingDirectory = workingDirectory?.standardizedFileURL
        self.requestedCommand = requestedCommand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.stagedCommand = stagedCommand?.nilIfBlankPreservingContent
        self.terminateHostedSessionOnClose = terminateHostedSessionOnClose
        self.currentDirectory = workingDirectory?.standardizedFileURL
        self.lastErrorDescription = nil
        self.startupPhase = startupPhase
    }

    public func requestKeyboardFocus() {
        focusRequestID &+= 1
        focusRequestHandler?(focusRequestID)
    }

    public func shutdown() {
        shutdownHandler?()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var nilIfBlankPreservingContent: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
