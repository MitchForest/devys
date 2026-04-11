import Foundation

public enum ACPAgentKind: String, CaseIterable, Codable, Sendable {
    case codex
    case claude

    public var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        }
    }
}

public struct ACPAgentDescriptor: Sendable, Equatable {
    public let kind: ACPAgentKind
    public let displayName: String
    public let executableName: String
    public let fallbackSearchNames: [String]

    public init(
        kind: ACPAgentKind,
        displayName: String,
        executableName: String,
        fallbackSearchNames: [String] = []
    ) {
        self.kind = kind
        self.displayName = displayName
        self.executableName = executableName
        self.fallbackSearchNames = fallbackSearchNames
    }

    public var searchNames: [String] {
        [executableName] + fallbackSearchNames
    }

    public static let supported: [ACPAgentDescriptor] = [
        ACPAgentDescriptor(
            kind: .codex,
            displayName: ACPAgentKind.codex.displayName,
            executableName: "codex-acp"
        ),
        ACPAgentDescriptor(
            kind: .claude,
            displayName: ACPAgentKind.claude.displayName,
            executableName: "claude-agent-acp"
        ),
    ]

    public static func descriptor(for kind: ACPAgentKind) -> ACPAgentDescriptor {
        guard let descriptor = supported.first(where: { $0.kind == kind }) else {
            preconditionFailure("Unsupported agent kind: \(kind.rawValue)")
        }
        return descriptor
    }
}

public struct ACPResolvedAdapter: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case configured
        case bundled
        case path
    }

    public let descriptor: ACPAgentDescriptor
    public let executableURL: URL
    public let source: Source

    public init(
        descriptor: ACPAgentDescriptor,
        executableURL: URL,
        source: Source
    ) {
        self.descriptor = descriptor
        self.executableURL = executableURL
        self.source = source
    }
}

public struct ACPAdapterLaunchOptions: Sendable, Equatable {
    public var configuredExecutableURL: URL?
    public var bundledExecutableSearchRoots: [URL]
    public var fallbackSearchDirectories: [URL]
    public var arguments: [String]
    public var environment: [String: String]
    public var currentDirectoryURL: URL?
    public var requiredCapabilities: [String]
    public var clientInfo: ACPImplementationInfo
    public var clientCapabilities: ACPClientCapabilities
    public var protocolVersion: ACPProtocolVersion

    public init(
        configuredExecutableURL: URL? = nil,
        bundledExecutableSearchRoots: [URL] = [],
        fallbackSearchDirectories: [URL] = [],
        arguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryURL: URL? = nil,
        requiredCapabilities: [String] = [],
        clientInfo: ACPImplementationInfo = ACPImplementationInfo(name: "Devys", version: nil),
        clientCapabilities: ACPClientCapabilities = ACPClientCapabilities(),
        protocolVersion: ACPProtocolVersion = ACPProtocolVersion.current
    ) {
        self.configuredExecutableURL = configuredExecutableURL
        self.bundledExecutableSearchRoots = bundledExecutableSearchRoots
        self.fallbackSearchDirectories = fallbackSearchDirectories
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
        self.requiredCapabilities = requiredCapabilities
        self.clientInfo = clientInfo
        self.clientCapabilities = clientCapabilities
        self.protocolVersion = protocolVersion
    }
}

public enum ACPInitializeFailure: Error, Sendable, Equatable {
    case transport(ACPTransportError)
    case remote(ACPRemoteError)
    case invalidResponse(String)
}

extension ACPInitializeFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .transport(let error):
            error.localizedDescription
        case .remote(let error):
            error.localizedDescription
        case .invalidResponse(let message):
            "The adapter returned an invalid initialize response: \(message)"
        }
    }
}

public enum ACPAdapterLaunchError: Error, Sendable, Equatable {
    case binaryNotFound(kind: ACPAgentKind, candidates: [String])
    case spawnFailed(executableURL: URL, reason: String)
    case initializeFailed(ACPInitializeFailure)
    case unsupportedProtocolVersion(expected: ACPProtocolVersion, actual: ACPProtocolVersion?)
    case unsupportedCapability(String)
}

extension ACPAdapterLaunchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let kind, let candidates):
            let joinedCandidates = candidates.map { "`\($0)`" }.joined(separator: ", ")
            return """
                No \(kind.displayName) ACP adapter was found. Expected \(joinedCandidates) in a \
                configured path, the app bundle helpers, or PATH.
                """
        case .spawnFailed(let executableURL, let reason):
            return "Failed to launch ACP adapter at \(executableURL.path): \(reason)"
        case .initializeFailed(let failure):
            return failure.localizedDescription
        case .unsupportedProtocolVersion(let expected, let actual):
            let actualDescription = actual.map { String($0.rawValue) } ?? "none"
            return "The adapter reported protocol version \(actualDescription), but Devys expects \(expected.rawValue)."
        case .unsupportedCapability(let capability):
            return "The adapter does not support required capability `\(capability)`."
        }
    }
}

public struct ACPLaunchedAdapter: Sendable {
    public let descriptor: ACPAgentDescriptor
    public let resolvedAdapter: ACPResolvedAdapter
    public let connection: ACPConnection
    public let initializeResult: ACPInitializeResult

    public init(
        descriptor: ACPAgentDescriptor,
        resolvedAdapter: ACPResolvedAdapter,
        connection: ACPConnection,
        initializeResult: ACPInitializeResult
    ) {
        self.descriptor = descriptor
        self.resolvedAdapter = resolvedAdapter
        self.connection = connection
        self.initializeResult = initializeResult
    }
}

public struct ACPAdapterLauncher: Sendable {
    public init() {}

    public func resolve(
        descriptor: ACPAgentDescriptor,
        options: ACPAdapterLaunchOptions = ACPAdapterLaunchOptions()
    ) throws -> ACPResolvedAdapter {
        if let configuredExecutableURL = options.configuredExecutableURL,
           isExecutableFile(at: configuredExecutableURL) {
            return ACPResolvedAdapter(
                descriptor: descriptor,
                executableURL: configuredExecutableURL,
                source: .configured
            )
        }

        for rootURL in options.bundledExecutableSearchRoots {
            for executableName in descriptor.searchNames {
                let candidate = rootURL.appending(path: executableName, directoryHint: .notDirectory)
                if isExecutableFile(at: candidate) {
                    return ACPResolvedAdapter(
                        descriptor: descriptor,
                        executableURL: candidate,
                        source: .bundled
                    )
                }
            }
        }

        if let executableURL = resolveFromPATH(
            names: descriptor.searchNames,
            environment: options.environment,
            fallbackSearchDirectories: options.fallbackSearchDirectories
        ) {
            return ACPResolvedAdapter(
                descriptor: descriptor,
                executableURL: executableURL,
                source: .path
            )
        }

        throw ACPAdapterLaunchError.binaryNotFound(
            kind: descriptor.kind,
            candidates: descriptor.searchNames
        )
    }

    public func launch(
        kind: ACPAgentKind,
        options: ACPAdapterLaunchOptions = ACPAdapterLaunchOptions()
    ) async throws -> ACPLaunchedAdapter {
        try await launch(
            descriptor: ACPAgentDescriptor.descriptor(for: kind),
            options: options
        )
    }

    public func launch(
        descriptor: ACPAgentDescriptor,
        options: ACPAdapterLaunchOptions = ACPAdapterLaunchOptions()
    ) async throws -> ACPLaunchedAdapter {
        let resolvedAdapter = try resolve(descriptor: descriptor, options: options)
        let transport = try makeTransport(
            resolvedAdapter: resolvedAdapter,
            options: options
        )
        let connection = ACPConnection(transport: transport)
        let initializeResult = try await performInitialize(
            connection: connection,
            options: options
        )
        if initializeResult.protocolVersion != options.protocolVersion {
            await connection.shutdown()
            throw ACPAdapterLaunchError.unsupportedProtocolVersion(
                expected: options.protocolVersion,
                actual: initializeResult.protocolVersion
            )
        }

        for capability in options.requiredCapabilities where !initializeResult.capabilities.supports(capability) {
            await connection.shutdown()
            throw ACPAdapterLaunchError.unsupportedCapability(capability)
        }

        return ACPLaunchedAdapter(
            descriptor: descriptor,
            resolvedAdapter: resolvedAdapter,
            connection: connection,
            initializeResult: initializeResult
        )
    }

    private func isExecutableFile(at url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    private func makeTransport(
        resolvedAdapter: ACPResolvedAdapter,
        options: ACPAdapterLaunchOptions
    ) throws -> ACPTransportStdio {
        do {
            return try ACPTransportStdio.launch(
                executableURL: resolvedAdapter.executableURL,
                arguments: options.arguments,
                environment: options.environment,
                currentDirectoryURL: options.currentDirectoryURL
            )
        } catch let error as ACPTransportError {
            let reason: String
            switch error {
            case .processSpawnFailed(let spawnReason):
                reason = spawnReason
            default:
                reason = String(describing: error)
            }

            throw ACPAdapterLaunchError.spawnFailed(
                executableURL: resolvedAdapter.executableURL,
                reason: reason
            )
        } catch {
            throw ACPAdapterLaunchError.spawnFailed(
                executableURL: resolvedAdapter.executableURL,
                reason: String(describing: error)
            )
        }
    }

    private func performInitialize(
        connection: ACPConnection,
        options: ACPAdapterLaunchOptions
    ) async throws -> ACPInitializeResult {
        do {
            return try await connection.initialize(
                clientInfo: options.clientInfo,
                capabilities: options.clientCapabilities,
                protocolVersion: options.protocolVersion
            )
        } catch let error as ACPTransportError {
            throw ACPAdapterLaunchError.initializeFailed(.transport(error))
        } catch let error as ACPRemoteError {
            throw ACPAdapterLaunchError.initializeFailed(.remote(error))
        } catch {
            throw ACPAdapterLaunchError.initializeFailed(
                .invalidResponse(String(describing: error))
            )
        }
    }

    private func resolveFromPATH(
        names: [String],
        environment: [String: String],
        fallbackSearchDirectories: [URL]
    ) -> URL? {
        let fallbackRootPaths = Set(
            fallbackSearchDirectories.map { directoryURL in
                directoryURL.standardizedFileURL.path(percentEncoded: false)
            }
        )
        var pathRoots: [String] = []
        var deferredFallbackRoots: [String] = []
        var seenRoots: Set<String> = []

        func appendPathEntries(_ rawPath: String?) {
            guard let rawPath else { return }
            for component in rawPath.split(separator: ":") {
                let path = String(component).trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedPath = URL(fileURLWithPath: path, isDirectory: true)
                    .standardizedFileURL
                    .path(percentEncoded: false)
                guard !normalizedPath.isEmpty,
                      seenRoots.insert(normalizedPath).inserted else {
                    continue
                }
                if fallbackRootPaths.contains(normalizedPath) {
                    deferredFallbackRoots.append(normalizedPath)
                } else {
                    pathRoots.append(normalizedPath)
                }
            }
        }

        appendPathEntries(environment["PATH"])
        appendPathEntries(ProcessInfo.processInfo.environment["PATH"])
        pathRoots.append(contentsOf: deferredFallbackRoots)

        for directoryURL in fallbackSearchDirectories {
            let path = directoryURL.standardizedFileURL.path(percentEncoded: false)
            guard !path.isEmpty,
                  seenRoots.insert(path).inserted else {
                continue
            }
            pathRoots.append(path)
        }

        for root in pathRoots {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            for name in names {
                let candidate = rootURL.appending(path: name, directoryHint: .notDirectory)
                guard isExecutableFile(at: candidate) else { continue }
                return candidate
            }
        }

        return nil
    }
}
