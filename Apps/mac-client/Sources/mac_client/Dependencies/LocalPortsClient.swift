import ComposableArchitecture
import Foundation

struct LocalPort: Equatable, Identifiable, Sendable {
    var port: Int
    var processID: Int32
    var processName: String
    var workingDirectory: URL?

    var id: String { "\(port)-\(processID)" }
}

struct LocalPortsClient: Sendable {
    var detect: @Sendable (URL) async throws -> [LocalPort]

    init(detect: @escaping @Sendable (URL) async throws -> [LocalPort]) {
        self.detect = detect
    }

    static let liveValue = LocalPortsClient { projectRootURL in
        let standardizedProjectRootURL = projectRootURL.standardizedFileURL
        return try await Task.detached(priority: .utility) {
            try detectSynchronously(projectRootURL: standardizedProjectRootURL)
        }.value
    }

    static func detectPorts(
        projectRootURL: URL,
        listeningOutput: String,
        parentProcessOutput: String,
        workingDirectoryOutput: String
    ) -> [LocalPort] {
        let records = parseListeningPorts(listeningOutput)
        guard !records.isEmpty else { return [] }

        let parentByProcessID = parseParentProcessMap(parentProcessOutput)
        let relevantProcessIDs = collectRelevantProcessIDs(
            from: records,
            parentByProcessID: parentByProcessID
        )
        let workingDirectoryByProcessID = parseWorkingDirectories(
            workingDirectoryOutput,
            allowedProcessIDs: Set(relevantProcessIDs)
        )

        return matchPorts(
            records: records,
            projectRootURL: projectRootURL.standardizedFileURL,
            parentByProcessID: parentByProcessID,
            workingDirectoryByProcessID: workingDirectoryByProcessID
        )
    }

    static func parseListeningPorts(_ output: String) -> [ListeningPortRecord] {
        var currentProcessID: Int32?
        var currentProcessName = ""
        var seen: Set<ListeningPortRecord> = []
        var result: [ListeningPortRecord] = []

        for line in output.split(whereSeparator: \.isNewline) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                currentProcessID = Int32(value)
                currentProcessName = ""
            case "c":
                currentProcessName = value
            case "n":
                guard let currentProcessID,
                      let port = parsePort(value) else {
                    continue
                }
                let record = ListeningPortRecord(
                    processID: currentProcessID,
                    processName: currentProcessName,
                    port: port
                )
                if seen.insert(record).inserted {
                    result.append(record)
                }
            default:
                continue
            }
        }

        return result
    }

    static func parseParentProcessMap(_ output: String) -> [Int32: Int32] {
        var result: [Int32: Int32] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2,
                  let pid = Int32(parts[0]),
                  let parentID = Int32(parts[1]) else {
                continue
            }
            result[pid] = parentID
        }
        return result
    }

    static func parseWorkingDirectories(
        _ output: String,
        allowedProcessIDs: Set<Int32>
    ) -> [Int32: URL] {
        var currentProcessID: Int32?
        var result: [Int32: URL] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                currentProcessID = Int32(value)
            case "n":
                guard let currentProcessID,
                      allowedProcessIDs.contains(currentProcessID) else {
                    continue
                }
                result[currentProcessID] = URL(fileURLWithPath: value).standardizedFileURL
            default:
                continue
            }
        }

        return result
    }

    private static func detectSynchronously(projectRootURL: URL) throws -> [LocalPort] {
        let listeningOutput = try runCommand(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]
        )
        let records = parseListeningPorts(listeningOutput)
        guard !records.isEmpty else { return [] }

        let parentByProcessID = (try? runCommand(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,ppid="]
        )).map(parseParentProcessMap) ?? [:]
        let relevantProcessIDs = collectRelevantProcessIDs(
            from: records,
            parentByProcessID: parentByProcessID
        )
        let workingDirectoryByProcessID = try loadWorkingDirectories(processIDs: relevantProcessIDs)

        return matchPorts(
            records: records,
            projectRootURL: projectRootURL,
            parentByProcessID: parentByProcessID,
            workingDirectoryByProcessID: workingDirectoryByProcessID
        )
    }

    private static func runCommand(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func loadWorkingDirectories(processIDs: [Int32]) throws -> [Int32: URL] {
        guard !processIDs.isEmpty else { return [:] }
        let pidList = processIDs.map(String.init).joined(separator: ",")
        let output = try runCommand(
            executable: "/usr/sbin/lsof",
            arguments: ["-a", "-d", "cwd", "-p", pidList, "-F", "pn"]
        )
        return parseWorkingDirectories(output, allowedProcessIDs: Set(processIDs))
    }

    private static func matchPorts(
        records: [ListeningPortRecord],
        projectRootURL: URL,
        parentByProcessID: [Int32: Int32],
        workingDirectoryByProcessID: [Int32: URL]
    ) -> [LocalPort] {
        var seenPorts: Set<Int> = []
        var ports: [LocalPort] = []

        for record in records.sorted(by: { $0.port < $1.port }) {
            guard !seenPorts.contains(record.port),
                  let matchingProcessID = matchingProcessID(
                    for: record.processID,
                    projectRootURL: projectRootURL,
                    parentByProcessID: parentByProcessID,
                    workingDirectoryByProcessID: workingDirectoryByProcessID
                  ) else {
                continue
            }

            seenPorts.insert(record.port)
            ports.append(
                LocalPort(
                    port: record.port,
                    processID: record.processID,
                    processName: record.processName.isEmpty ? "process \(record.processID)" : record.processName,
                    workingDirectory: workingDirectoryByProcessID[matchingProcessID]
                )
            )
        }

        return ports
    }

    private static func collectRelevantProcessIDs(
        from records: [ListeningPortRecord],
        parentByProcessID: [Int32: Int32]
    ) -> [Int32] {
        var result: Set<Int32> = []
        for record in records {
            var current = record.processID
            var visited: Set<Int32> = []

            while current > 0, visited.insert(current).inserted {
                result.insert(current)
                guard let parent = parentByProcessID[current],
                      parent != current else {
                    break
                }
                current = parent
            }
        }
        return result.sorted()
    }

    private static func matchingProcessID(
        for processID: Int32,
        projectRootURL: URL,
        parentByProcessID: [Int32: Int32],
        workingDirectoryByProcessID: [Int32: URL]
    ) -> Int32? {
        var current = processID
        var visited: Set<Int32> = []

        while current > 0, visited.insert(current).inserted {
            if let workingDirectory = workingDirectoryByProcessID[current],
               workingDirectory.isDescendant(of: projectRootURL) {
                return current
            }
            guard let parent = parentByProcessID[current],
                  parent != current else {
                break
            }
            current = parent
        }

        return nil
    }

    private static func parsePort(_ value: String) -> Int? {
        let cleaned = value.replacingOccurrences(of: " (LISTEN)", with: "")
        guard let colonIndex = cleaned.lastIndex(of: ":") else { return nil }
        let suffix = cleaned[cleaned.index(after: colonIndex)...]
        let digits = suffix.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}

private enum LocalPortsClientKey: DependencyKey {
    static let liveValue = LocalPortsClient.liveValue
}

extension DependencyValues {
    var localPortsClient: LocalPortsClient {
        get { self[LocalPortsClientKey.self] }
        set { self[LocalPortsClientKey.self] = newValue }
    }
}

struct ListeningPortRecord: Hashable, Sendable {
    let processID: Int32
    let processName: String
    let port: Int
}

private extension URL {
    func isDescendant(of parent: URL) -> Bool {
        let path = standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return path == parentPath || path.hasPrefix(parentPath + "/")
    }
}
