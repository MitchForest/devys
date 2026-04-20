import Foundation
import Darwin

enum TerminalSessionLaunchError: LocalizedError, Sendable {
    case missingBundledTerminfo

    var errorDescription: String? {
        switch self {
        case .missingBundledTerminfo:
            return "Missing bundled xterm-ghostty terminfo directory."
        }
    }
}

struct TerminalSessionLaunchContext: Sendable {
    let environmentKeysToUnset: [String]
    let environmentAssignments: [TerminalSessionEnvironmentAssignment]
    let executablePath: String
    let arguments: [String]
}

struct TerminalSessionEnvironmentAssignment: Sendable {
    let key: String
    let value: String
}

enum TerminalSessionLaunchProfile: String, Codable, Equatable, Sendable {
    case fastShell = "fast_shell"
    case compatibilityShell = "compatibility_shell"
}

func terminalSessionEnvironmentAssignments() throws -> [String: String] {
    guard let terminfoDirectory = terminalSessionTerminfoDirectory() else {
        throw TerminalSessionLaunchError.missingBundledTerminfo
    }

    var assignments = [
        "COLORTERM": "truecolor",
        "COLORFGBG": terminalSessionColorFgBg(),
        "TERM": "xterm-ghostty",
        "TERMINFO": terminfoDirectory,
        "TERM_PROGRAM": "ghostty",
    ]

    if let termProgramVersion = terminalSessionTermProgramVersion() {
        assignments["TERM_PROGRAM_VERSION"] = termProgramVersion
    }

    return assignments
}

func terminalSessionTerminfoDirectory() -> String? {
    let candidateResourceURLs = terminalSessionCandidateResourceURLs(
        environment: ProcessInfo.processInfo.environment,
        currentExecutablePath: terminalHostCurrentExecutablePath(),
        bundleResourceURLs: ([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks)
            .compactMap(\.resourceURL),
        appBundleResourceURL: Bundle(identifier: "com.devys.mac")?.resourceURL
    )

    for resourceURL in candidateResourceURLs {
        let terminfoURL = resourceURL.appendingPathComponent("terminfo", isDirectory: true)
        let path = terminfoURL.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }

    return nil
}

func terminalSessionCandidateResourceURLs(
    environment: [String: String],
    currentExecutablePath: String?,
    bundleResourceURLs: [URL],
    appBundleResourceURL: URL?
) -> [URL] {
    let explicitResourceURLs = [
        terminalSessionExplicitResourceDirectory(path: environment["DEVYS_RESOURCE_DIR"]),
        terminalSessionResourceDirectory(executablePath: currentExecutablePath),
        Bundle.main.resourceURL,
        appBundleResourceURL,
        terminalSessionResourceDirectory(executablePath: environment["TEST_HOST"]),
        terminalSessionResourceDirectory(executablePath: environment["BUNDLE_LOADER"]),
        terminalSessionSourceResourceDirectory(
            isTesting: environment["XCTestConfigurationFilePath"] != nil
        ),
    ]

    return uniqueResourceURLs(explicitResourceURLs + bundleResourceURLs)
}

private func terminalSessionExplicitResourceDirectory(path: String?) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    return URL(filePath: path, directoryHint: .isDirectory)
}

func terminalSessionResourceDirectory(executablePath: String?) -> URL? {
    guard let executablePath, !executablePath.isEmpty else {
        return nil
    }

    return URL(filePath: executablePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
}

private func uniqueResourceURLs(_ urls: [URL?]) -> [URL] {
    var seenPaths = Set<String>()
    var result: [URL] = []

    for url in urls.compactMap({ $0 }) {
        let path = url.path(percentEncoded: false)
        if seenPaths.insert(path).inserted {
            result.append(url)
        }
    }

    return result
}

private func terminalSessionSourceResourceDirectory(isTesting: Bool) -> URL? {
    guard isTesting else { return nil }

    return URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources", isDirectory: true)
}

func terminalSessionEnvironmentKeysToUnset() -> [String] {
    colorSuppressingEnvironmentKeysList()
}

func terminalSessionTermProgramVersion() -> String? {
    let infoDictionary = Bundle.main.infoDictionary
    let shortVersion = infoDictionary?["CFBundleShortVersionString"] as? String
    if let shortVersion,
       !shortVersion.isEmpty {
        return shortVersion
    }

    let bundleVersion = infoDictionary?["CFBundleVersion"] as? String
    if let bundleVersion,
       !bundleVersion.isEmpty {
        return bundleVersion
    }

    return nil
}

func terminalSessionColorFgBg() -> String {
    let environment = ProcessInfo.processInfo.environment
    if let colorFgBg = environment["COLORFGBG"],
       !colorFgBg.isEmpty {
        return colorFgBg
    }

    return "15;0"
}

func resolvedTerminalShellPath(environment: [String: String]) -> String {
    guard let shellPath = environment["SHELL"],
          shellPath.hasPrefix("/"),
          !shellPath.isEmpty
    else {
        return "/bin/zsh"
    }
    return shellPath
}

func terminalShellLaunchConfiguration(
    launchProfile: TerminalSessionLaunchProfile,
    launchCommand: String?,
    environment: [String: String]
) -> (executablePath: String, arguments: [String]) {
    let executablePath = resolvedTerminalShellPath(environment: environment)
    let shellName = executablePath.split(separator: "/").last.map(String.init) ?? executablePath

    switch launchProfile {
    case .fastShell:
        if let launchCommand,
           !launchCommand.isEmpty {
            return (executablePath, [shellName, "-i", "-c", launchCommand])
        }
        return (executablePath, [shellName, "-i"])
    case .compatibilityShell:
        if let launchCommand,
           !launchCommand.isEmpty {
            return (executablePath, [shellName, "-i", "-l", "-c", launchCommand])
        }
        return (executablePath, [shellName, "-i", "-l"])
    }
}

func makeTerminalSessionLaunchContext(
    launchProfile: TerminalSessionLaunchProfile,
    launchCommand: String?
) throws -> TerminalSessionLaunchContext {
    let environment = ProcessInfo.processInfo.environment
    return TerminalSessionLaunchContext(
        environmentKeysToUnset: terminalSessionEnvironmentKeysToUnset(),
        environmentAssignments: try terminalSessionEnvironmentAssignments().map {
            TerminalSessionEnvironmentAssignment(key: $0.key, value: $0.value)
        },
        executablePath: terminalShellLaunchConfiguration(
            launchProfile: launchProfile,
            launchCommand: launchCommand,
            environment: environment
        ).executablePath,
        arguments: terminalShellLaunchConfiguration(
            launchProfile: launchProfile,
            launchCommand: launchCommand,
            environment: environment
        ).arguments
    )
}

func runTerminalSessionChild(
    workingDirectoryPath: String?,
    launchContext: TerminalSessionLaunchContext
) -> Never {
    if let workingDirectoryPath {
        _ = workingDirectoryPath.withCString { Darwin.chdir($0) }
    }

    applyTerminalSessionEnvironment(launchContext)
    execShell(launchContext)
}

private func applyTerminalSessionEnvironment(_ launchContext: TerminalSessionLaunchContext) {
    for key in launchContext.environmentKeysToUnset {
        _ = key.withCString { unsetenv($0) }
    }
    for assignment in launchContext.environmentAssignments {
        _ = assignment.key.withCString { key in
            assignment.value.withCString { value in
                setenv(key, value, 1)
            }
        }
    }
}

private func execShell(_ launchContext: TerminalSessionLaunchContext) -> Never {
    let arguments = launchContext.arguments

    var cArguments = arguments.map { strdup($0) }
    cArguments.append(nil)
    defer {
        for pointer in cArguments {
            free(pointer)
        }
    }

    _ = launchContext.executablePath.withCString { executable in
        cArguments.withUnsafeMutableBufferPointer { buffer in
            execv(executable, buffer.baseAddress)
        }
    }
    _exit(127)
}
