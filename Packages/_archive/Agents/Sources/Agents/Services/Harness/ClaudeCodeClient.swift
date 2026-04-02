// ClaudeCodeClient.swift
// Thin wrapper for Claude Code CLI stream-json mode.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Logging

/// Manages communication with Claude Code CLI via stream-json protocol.
///
/// Claude Code uses NDJSON (newline-delimited JSON) over stdio:
/// - Input: User messages and approval responses
/// - Output: Streaming events, tool calls, approval requests
///
/// ## Invocation
/// ```bash
/// claude -p \
///   --input-format=stream-json \
///   --output-format=stream-json \
///   --permission-prompt-tool=stdio \
///   --permission-mode=default \
///   --verbose \
///   --include-partial-messages \
///   --model claude-opus-4-5-20251101
/// ```
actor ClaudeCodeClient {

    // MARK: - Types

    enum State: Sendable, Equatable {
        case idle
        case starting
        case ready
        case error(String)
        case stopped
    }

    enum PermissionMode: String, Sendable {
        case `default` = "default"
        case acceptEdits = "acceptEdits"
        case plan = "plan"
        case dontAsk = "dontAsk"
        case bypassPermissions = "bypassPermissions"
    }

    // MARK: - Properties

    private(set) var state: State = .idle {
        didSet {
            logger.info("ClaudeCodeClient state: \(oldValue) -> \(state)")
        }
    }

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    
    /// Buffer for accumulating partial lines from stdout.
    private var stdoutBuffer = Data()

    private let eventContinuation: AsyncStream<ClaudeCodeEvent>.Continuation
    nonisolated let events: AsyncStream<ClaudeCodeEvent>

    private let logger = Logger(label: "devys.claude")
    
    /// Count of events yielded for debugging.
    private var eventsYielded = 0
    
    /// Count of lines read from stdout.
    private var linesRead = 0

    // MARK: - Initialization

    init() {
        var continuation: AsyncStream<ClaudeCodeEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
        logger.info("ClaudeCodeClient initialized")
    }

    // MARK: - Lifecycle

    func start(
        cwd: String,
        model: LLMModel,
        permissionMode: PermissionMode = .default,
        resumeSessionId: String? = nil
    ) async throws {
        let resumeText = resumeSessionId ?? "nil"
        logger.info(
            "ClaudeCodeClient.start() called - cwd: \(cwd), model: \(model.rawValue), resumeSessionId: \(resumeText)"
        )
        
        guard state == .idle || state == .stopped else {
            logger.warning("ClaudeCodeClient.start() ignored - already in state: \(state)")
            return
        }

        state = .starting

        let claudePath = try resolveClaudePath()
        let process = configureProcess(
            path: claudePath,
            cwd: cwd,
            model: model,
            permissionMode: permissionMode,
            resumeSessionId: resumeSessionId
        )
        let stderrPipe = configurePipes(process)
        configureHandlers(process, stderrPipe: stderrPipe)

        // Start process
        try runProcess(process)

        self.process = process
        state = .ready
        logger.info("Claude Code ready - waiting for events...")

        // Start reading events using callback-based approach for reliability
        logger.debug("Setting up stdout readability handler...")
        setupStdoutHandler()
    }

    private func resolveClaudePath() throws -> String {
        do {
            let claudePath = try findClaudeBinary()
            logger.info("Found Claude binary at: \(claudePath)")
            return claudePath
        } catch {
            logger.error("Failed to find Claude binary: \(error)")
            state = .error("Claude binary not found: \(error.localizedDescription)")
            throw error
        }
    }

    private func configureProcess(
        path: String,
        cwd: String,
        model: LLMModel,
        permissionMode: PermissionMode,
        resumeSessionId: String?
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)

        var arguments: [String] = [
            "-p",
            "--input-format=stream-json",
            "--output-format=stream-json",
            "--permission-prompt-tool=stdio",
            "--permission-mode=\(permissionMode.rawValue)",
            "--verbose",
            "--include-partial-messages",
            "--replay-user-messages",
            "--model",
            model.rawValue
        ]

        if let resumeSessionId {
            arguments.append(contentsOf: ["--resume", resumeSessionId])
        }

        logger.info("Claude arguments: \(arguments.joined(separator: " "))")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = makeClaudeEnvironment()

        return process
    }

    private func makeClaudeEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["CLAUDE_CODE_ENABLE_TELEMETRY"] = "false"
        env["CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS"] = "true"
        env["CLAUDE_CODE_DISABLE_BACKGROUND_TASKS"] = "true"
        env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] = "true"
        env["CLAUDE_CODE_HIDE_ACCOUNT_INFO"] = "true"
        return env
    }

    private func configurePipes(_ process: Process) -> Pipe {
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdin = stdinPipe.fileHandleForWriting
        stdout = stdoutPipe.fileHandleForReading

        logger.debug("Pipes configured - stdin/stdout/stderr ready")
        return stderrPipe
    }

    private func configureHandlers(_ process: Process, stderrPipe: Pipe) {
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                Task { [weak self] in
                    await self?.logStderr(str)
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            Task { [weak self] in
                await self?.handleTermination(exitCode: proc.terminationStatus)
            }
        }
    }

    private func runProcess(_ process: Process) throws {
        logger.info("Starting Claude process...")
        do {
            try process.run()
            logger.info("Claude process started successfully - PID: \(process.processIdentifier)")
        } catch {
            logger.error("Failed to start Claude process: \(error)")
            state = .error("Failed to start: \(error.localizedDescription)")
            throw error
        }
    }
    
    func stop() async {
        logger.info("ClaudeCodeClient.stop() called - current state: \(state)")
        
        // Clear readability handlers first
        stdout?.readabilityHandler = nil
        stdoutBuffer.removeAll()
        
        if let process = process, process.isRunning {
            logger.info("Terminating Claude process PID: \(process.processIdentifier)")
            process.terminate()
        }
        process = nil
        stdin = nil
        stdout = nil
        state = .stopped
        eventContinuation.finish()
        logger.info("Claude Code stopped - yielded \(eventsYielded) events total, read \(linesRead) lines")
    }

    // MARK: - Communication

    /// Sends a user query to Claude.
    func query(prompt: String) async throws {
        logger.info("ClaudeCodeClient.query() - prompt length: \(prompt.count) chars")
        let message: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": prompt
            ]
        ]
        try writeMessage(message)
    }

    /// Responds to an approval request (control_request -> control_response).
    func respondToApproval(requestId: String, decision: ClaudeApprovalDecision) async throws {
        logger.info("ClaudeCodeClient.respondToApproval() - requestId: \(requestId), decision: \(decision)")
        
        // Claude Code expects control_response with permission object
        // Format: {"type":"control_response","request_id":"...","permission":{"type":"allow"}}
        let permissionType: String
        switch decision {
        case .approve:
            permissionType = "allow"
        case .deny:
            permissionType = "deny"
        }
        
        let message: [String: Any] = [
            "type": "control_response",
            "request_id": requestId,
            "permission": [
                "type": permissionType
            ]
        ]
        try writeMessage(message)
    }

    /// Responds to a user input request (control_request ask_user_question).
    func respondToUserInput(requestId: String, answers: [String]) async throws {
        logger.info("ClaudeCodeClient.respondToUserInput() - requestId: \(requestId), answers: \(answers.count)")

        let responsePayload: [String: Any] = [
            "type": "control_response",
            "response": [
                "subtype": "success",
                "request_id": requestId,
                "response": [
                    "answers": answers
                ]
            ]
        ]

        try writeMessage(responsePayload)
    }

    // MARK: - IO

    private func writeMessage(_ message: [String: Any]) throws {
        guard let stdin = stdin else {
            logger.error("writeMessage failed - stdin is nil")
            throw ClaudeCodeError.notReady
        }

        let data = try JSONSerialization.data(withJSONObject: message)
        var dataWithNewline = data
        dataWithNewline.append(contentsOf: "\n".utf8)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            logger.debug("STDIN >>> \(jsonString)")
        }
        
        stdin.write(dataWithNewline)
    }

    // MARK: - Helpers

    private func findClaudeBinary() throws -> String {
        let paths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/local/claude").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
        ]
        
        logger.debug("Searching for Claude binary in: \(paths)")

        for path in paths {
            let exists = FileManager.default.isExecutableFile(atPath: path)
            logger.debug("  \(path): \(exists ? "FOUND" : "not found")")
            if exists {
                return path
            }
        }

        // Try `which` as fallback
        logger.debug("Trying `which claude` as fallback...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0,
           let data = try? pipe.fileHandleForReading.readToEnd(),
           let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            logger.debug("`which` found Claude at: \(path)")
            return path
        }
        
        logger.error("Claude binary not found in any location")
        throw ClaudeCodeError.binaryNotFound
    }

    private func handleTermination(exitCode: Int32) {
        logger.info("Claude process terminated - exitCode: \(exitCode), previousState: \(state)")
        if exitCode != 0 && state == .ready {
            state = .error("Exited with code \(exitCode)")
            logger.error("Claude Code terminated unexpectedly with code: \(exitCode)")
        } else {
            state = .stopped
        }
        logger.info("After termination - linesRead: \(linesRead), eventsYielded: \(eventsYielded)")
    }

    private func logStderr(_ message: String) {
        // Log each line separately for clarity
        let lines = message.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in lines {
            logger.warning("STDERR: \(line)")
        }
    }

}

// MARK: - Stdout Handling

extension ClaudeCodeClient {
    /// Sets up callback-based reading from stdout.
    /// This is more reliable than async iteration for real-time streaming.
    func setupStdoutHandler() {
        guard let stdout = stdout else {
            logger.error("setupStdoutHandler() - stdout is nil")
            return
        }

        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData

            if data.isEmpty {
                Task { [weak self] in
                    await self?.handleStdoutEOF()
                }
                return
            }

            Task { [weak self] in
                await self?.handleStdoutData(data)
            }
        }

        logger.info("Stdout readability handler configured")
    }

    /// Handles incoming data from stdout.
    func handleStdoutData(_ data: Data) {
        stdoutBuffer.append(data)

        // Process complete lines (split by newline)
        while let newlineIndex = stdoutBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = stdoutBuffer[..<newlineIndex]
            stdoutBuffer.removeSubrange(...newlineIndex)

            processLine(lineData)
        }
    }

    /// Handles EOF on stdout.
    func handleStdoutEOF() {
        logger.info("Stdout EOF received")

        if !stdoutBuffer.isEmpty {
            processLine(stdoutBuffer)
            stdoutBuffer.removeAll()
        }

        stdout?.readabilityHandler = nil
    }

    /// Processes a single line of JSON from stdout.
    func processLine(_ lineData: Data) {
        linesRead += 1

        guard let line = String(data: lineData, encoding: .utf8) else {
            logger.warning("Line \(linesRead): Failed to decode as UTF-8")
            return
        }

        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return }

        logger.debug("STDOUT [\(linesRead)] <<< \(trimmedLine.prefix(500))...")

        guard let jsonData = trimmedLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            logger.warning("Line \(linesRead): Failed to parse as JSON - raw: \(trimmedLine.prefix(200))")
            return
        }

        let events = ClaudeCodeEvent.parseEvents(from: json)
        logger.debug("Line \(linesRead): Parsed \(events.count) event(s)")

        for event in events {
            eventsYielded += 1
            if eventsYielded <= 5 || eventsYielded.isMultiple(of: 20) {
                logger.debug("Yielding event #\(eventsYielded): \(String(describing: event).prefix(100))")
            }
            eventContinuation.yield(event)
        }
    }
}

// MARK: - Approval Decision

enum ClaudeApprovalDecision: String, Sendable {
    case approve
    case deny
}

// MARK: - Errors

enum ClaudeCodeError: Error, LocalizedError {
    case binaryNotFound
    case notReady

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Claude CLI not found. Install from: https://docs.anthropic.com/en/docs/claude-code/cli-reference"
        case .notReady:
            return "Claude Code is not ready"
        }
    }
}
