public import Foundation

public struct TerminalID: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var id: String { rawValue }
}

public struct TerminalSessionHandle: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public struct TerminalViewportSize: Codable, Equatable, Sendable {
    public var cols: Int
    public var rows: Int

    public init(cols: Int = 80, rows: Int = 24) {
        self.cols = max(1, cols)
        self.rows = max(1, rows)
    }
}

public struct TerminalLaunchDescriptor: Codable, Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]
    public var workingDirectoryPath: String?
    public var environment: [String: String]

    public init(
        executablePath: String,
        arguments: [String],
        workingDirectoryPath: String? = nil,
        environment: [String: String] = [:]
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectoryPath = workingDirectoryPath
        self.environment = environment
    }

    public static func userShell(
        workingDirectoryPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TerminalLaunchDescriptor {
        let executablePath = resolvedShellPath(environment: environment)
        let shellName = URL(fileURLWithPath: executablePath).lastPathComponent
        return TerminalLaunchDescriptor(
            executablePath: executablePath,
            arguments: [shellName, "-i", "-l"],
            workingDirectoryPath: workingDirectoryPath,
            environment: [:]
        )
    }

    public static func explicitCommand(
        executablePath: String,
        arguments: [String],
        workingDirectoryPath: String? = nil,
        environment: [String: String] = [:]
    ) -> TerminalLaunchDescriptor {
        TerminalLaunchDescriptor(
            executablePath: executablePath,
            arguments: arguments.isEmpty ? [URL(fileURLWithPath: executablePath).lastPathComponent] : arguments,
            workingDirectoryPath: workingDirectoryPath,
            environment: environment
        )
    }

    private static func resolvedShellPath(environment: [String: String]) -> String {
        guard let shellPath = environment["SHELL"],
              shellPath.hasPrefix("/"),
              !shellPath.isEmpty
        else {
            return "/bin/zsh"
        }
        return shellPath
    }
}

public struct TerminalProcessIdentity: Codable, Equatable, Sendable {
    public var processID: Int32
    public var parentProcessID: Int32?
    public var executablePath: String?
    public var executableName: String?
    public var arguments: [String]

    public init(
        processID: Int32,
        parentProcessID: Int32? = nil,
        executablePath: String? = nil,
        executableName: String? = nil,
        arguments: [String] = []
    ) {
        self.processID = processID
        self.parentProcessID = parentProcessID
        self.executablePath = executablePath
        self.executableName = executableName
        self.arguments = arguments
    }
}

public struct TerminalListeningPort: Codable, Equatable, Sendable {
    public var port: Int
    public var address: String?
    public var processID: Int32?

    public init(port: Int, address: String? = nil, processID: Int32? = nil) {
        self.port = port
        self.address = address
        self.processID = processID
    }
}

public struct TerminalProcessSnapshot: Codable, Equatable, Sendable {
    public var shellProcessID: Int32?
    public var foregroundProcess: TerminalProcessIdentity?
    public var processTree: [TerminalProcessIdentity]
    public var listeningPorts: [TerminalListeningPort]

    public init(
        shellProcessID: Int32? = nil,
        foregroundProcess: TerminalProcessIdentity? = nil,
        processTree: [TerminalProcessIdentity] = [],
        listeningPorts: [TerminalListeningPort] = []
    ) {
        self.shellProcessID = shellProcessID
        self.foregroundProcess = foregroundProcess
        self.processTree = processTree
        self.listeningPorts = listeningPorts
    }
}

public enum TerminalActivity: String, Codable, Equatable, Sendable {
    case idle
    case output
    case bell
}

public struct TerminalSnapshot: Codable, Equatable, Sendable {
    public var terminalID: TerminalID
    public var currentDirectoryPath: String?
    public var title: String?
    public var shellProcessID: Int32?
    public var foregroundProcess: TerminalProcessIdentity?
    public var processTree: [TerminalProcessIdentity]
    public var listeningPorts: [TerminalListeningPort]
    public var exit: TerminalExit?
    public var activity: TerminalActivity
    public var timestamp: Date

    public init(
        terminalID: TerminalID,
        currentDirectoryPath: String? = nil,
        title: String? = nil,
        shellProcessID: Int32? = nil,
        foregroundProcess: TerminalProcessIdentity? = nil,
        processTree: [TerminalProcessIdentity] = [],
        listeningPorts: [TerminalListeningPort] = [],
        exit: TerminalExit? = nil,
        activity: TerminalActivity = .idle,
        timestamp: Date = Date()
    ) {
        self.terminalID = terminalID
        self.currentDirectoryPath = currentDirectoryPath
        self.title = title
        self.shellProcessID = shellProcessID
        self.foregroundProcess = foregroundProcess
        self.processTree = processTree
        self.listeningPorts = listeningPorts
        self.exit = exit
        self.activity = activity
        self.timestamp = timestamp
    }
}

public enum TerminalPTYEvent: Equatable, Sendable {
    case output(Data)
    case exited(TerminalExit)
}

public struct TerminalExit: Codable, Equatable, Sendable {
    public var exitCode: Int?
    public var signal: Int?

    public init(exitCode: Int?, signal: Int?) {
        self.exitCode = exitCode
        self.signal = signal
    }
}

public enum TerminalStatus: String, Codable, Equatable, Sendable {
    case starting
    case running
    case exited
    case failed
}

public struct TerminalSurfaceCallbacks: Sendable {
    public var titleChanged: @MainActor @Sendable (String) -> Void
    public var currentDirectoryChanged: @MainActor @Sendable (String?) -> Void
    public var snapshotChanged: @MainActor @Sendable (TerminalSnapshot) -> Void
    public var statusChanged: @MainActor @Sendable (TerminalStatus) -> Void
    public var selectionChanged: @MainActor @Sendable (String?) -> Void
    public var bell: @MainActor @Sendable () -> Void
    public var exited: @MainActor @Sendable (TerminalExit) -> Void

    public init(
        titleChanged: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        currentDirectoryChanged: @escaping @MainActor @Sendable (String?) -> Void = { _ in },
        snapshotChanged: @escaping @MainActor @Sendable (TerminalSnapshot) -> Void = { _ in },
        statusChanged: @escaping @MainActor @Sendable (TerminalStatus) -> Void = { _ in },
        selectionChanged: @escaping @MainActor @Sendable (String?) -> Void = { _ in },
        bell: @escaping @MainActor @Sendable () -> Void = {},
        exited: @escaping @MainActor @Sendable (TerminalExit) -> Void = { _ in }
    ) {
        self.titleChanged = titleChanged
        self.currentDirectoryChanged = currentDirectoryChanged
        self.snapshotChanged = snapshotChanged
        self.statusChanged = statusChanged
        self.selectionChanged = selectionChanged
        self.bell = bell
        self.exited = exited
    }
}

public enum TerminalError: LocalizedError, Sendable {
    case unsupportedPlatform
    case failedToCreatePTY
    case sessionNotFound(UUID)
    case writeFailed(Int32)
    case resizeFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            "Local PTY sessions are only supported on macOS."
        case .failedToCreatePTY:
            "Could not create a local PTY session."
        case .sessionNotFound(let id):
            "Terminal session \(id.uuidString) was not found."
        case .writeFailed(let code):
            "Could not write terminal input (\(code))."
        case .resizeFailed(let code):
            "Could not resize terminal session (\(code))."
        }
    }
}
