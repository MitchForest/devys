import Foundation

struct SSHConfigHostOption: Identifiable, Equatable {
    let alias: String
    let hostName: String?
    let user: String?
    let port: String?
    let sourcePath: String

    var id: String { alias }

    var detailLine: String {
        var segments: [String] = []
        if let user, !user.isEmpty {
            segments.append(user)
        }
        if let hostName, !hostName.isEmpty {
            if let user, !user.isEmpty {
                segments[segments.count - 1] = "\(user)@\(hostName)"
            } else {
                segments.append(hostName)
            }
        }
        if let port, !port.isEmpty {
            segments.append("port \(port)")
        }
        if segments.isEmpty {
            return sourcePath
        }
        return segments.joined(separator: " · ")
    }
}

enum SSHConfigHostDiscovery {
    static func loadHosts(
        fileManager: FileManager = .default
    ) -> [SSHConfigHostOption] {
        let rootURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/config", isDirectory: false)
        var visited: Set<URL> = []
        return parseConfig(
            at: rootURL,
            fileManager: fileManager,
            visited: &visited
        )
    }

    private static func parseConfig(
        at url: URL,
        fileManager: FileManager,
        visited: inout Set<URL>
    ) -> [SSHConfigHostOption] {
        let normalizedURL = url.standardizedFileURL
        guard visited.insert(normalizedURL).inserted,
              let contents = try? String(contentsOf: normalizedURL, encoding: .utf8) else {
            return []
        }

        var state = ParseState(sourcePath: normalizedURL.path)

        for rawLine in contents.components(separatedBy: .newlines) {
            processLine(
                rawLine,
                relativeTo: normalizedURL.deletingLastPathComponent(),
                fileManager: fileManager,
                visited: &visited,
                state: &state
            )
        }

        state.flushCurrentHost()
        return deduplicatedHosts(from: state.discoveredHosts)
    }

    private static func stripComment(
        from line: String
    ) -> String {
        guard let commentRange = line.range(of: "#") else {
            return line
        }
        return String(line[..<commentRange.lowerBound])
    }

    private static func isConcreteHostAlias(
        _ alias: String
    ) -> Bool {
        !alias.isEmpty
            && !alias.contains("*")
            && !alias.contains("?")
            && !alias.hasPrefix("!")
    }

    private static func resolveIncludePatterns(
        _ value: String,
        relativeTo baseDirectoryURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        value
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .flatMap { pattern in
                resolvedURLs(
                    matching: pattern,
                    relativeTo: baseDirectoryURL,
                    fileManager: fileManager
                )
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func resolvedURLs(
        matching pattern: String,
        relativeTo baseDirectoryURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        let expandedPattern = NSString(string: pattern).expandingTildeInPath
        let patternURL: URL
        if expandedPattern.hasPrefix("/") {
            patternURL = URL(fileURLWithPath: expandedPattern, isDirectory: false)
        } else {
            patternURL = baseDirectoryURL.appendingPathComponent(expandedPattern, isDirectory: false)
        }

        let filePath = patternURL.path
        guard filePath.contains("*") || filePath.contains("?") else {
            return fileManager.fileExists(atPath: filePath) ? [patternURL] : []
        }

        let directoryURL = patternURL.deletingLastPathComponent()
        let filePattern = patternURL.lastPathComponent
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return []
        }

        let regex = wildcardRegex(for: filePattern)
        return entries.filter { entry in
            entry.lastPathComponent.range(of: regex, options: .regularExpression) != nil
        }
    }

    private static func wildcardRegex(
        for pattern: String
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let wildcardExpanded = escaped
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return "^\(wildcardExpanded)$"
    }
}

private extension SSHConfigHostDiscovery {
    static func processLine(
        _ rawLine: String,
        relativeTo baseDirectoryURL: URL,
        fileManager: FileManager,
        visited: inout Set<URL>,
        state: inout ParseState
    ) {
        let line = stripComment(from: rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        let pieces = line.split(maxSplits: 1, omittingEmptySubsequences: true) { $0.isWhitespace }
            .map(String.init)
        guard let key = pieces.first?.lowercased() else { return }
        let value = pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        switch key {
        case "include":
            state.flushCurrentHost()
            for includeURL in resolveIncludePatterns(value, relativeTo: baseDirectoryURL, fileManager: fileManager) {
                state.discoveredHosts.append(
                    contentsOf: parseConfig(at: includeURL, fileManager: fileManager, visited: &visited)
                )
            }

        case "host":
            state.flushCurrentHost()
            state.currentAliases = value
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter(isConcreteHostAlias)

        case "match":
            state.flushCurrentHost()

        case "hostname":
            if !state.currentAliases.isEmpty {
                state.currentHostName = value
            }

        case "user":
            if !state.currentAliases.isEmpty {
                state.currentUser = value
            }

        case "port":
            if !state.currentAliases.isEmpty {
                state.currentPort = value
            }

        default:
            break
        }
    }

    static func deduplicatedHosts(
        from hosts: [SSHConfigHostOption]
    ) -> [SSHConfigHostOption] {
        var seenAliases: Set<String> = []
        return hosts.filter { option in
            seenAliases.insert(option.alias).inserted
        }
    }
}

private struct ParseState {
    let sourcePath: String
    var discoveredHosts: [SSHConfigHostOption] = []
    var currentAliases: [String] = []
    var currentHostName: String?
    var currentUser: String?
    var currentPort: String?

    mutating func flushCurrentHost() {
        guard !currentAliases.isEmpty else { return }
        for alias in currentAliases {
            discoveredHosts.append(
                SSHConfigHostOption(
                    alias: alias,
                    hostName: currentHostName,
                    user: currentUser,
                    port: currentPort,
                    sourcePath: sourcePath
                )
            )
        }
        currentAliases = []
        currentHostName = nil
        currentUser = nil
        currentPort = nil
    }
}
