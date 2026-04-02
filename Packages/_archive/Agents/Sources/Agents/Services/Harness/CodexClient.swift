// CodexClient.swift
// Swift wrapper for the Codex App Server subprocess.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Logging

/// Manages communication with the Codex App Server via JSON-RPC over stdio.
///
/// Codex App Server provides:
/// - Agent loop with reasoning and planning
/// - Built-in tools (bash, read, write, edit, grep, glob, web_search)
/// - Skills system (skills/list, skills/config/write)
/// - Thread/Turn management with persistence
/// - Sandbox and approval handling
///
/// ## Invocation
/// ```bash
/// codex app-server \
///   --enable collab \
///   --enable child_agents_md \
///   -c 'model="gpt-5.2-codex"'
/// ```
actor CodexClient {

    // MARK: - Types

    enum State: Sendable, Equatable {
        case idle
        case starting
        case ready
        case error(String)
        case stopped
    }

    // MARK: - Properties

    private(set) var state: State = .idle {
        didSet {
            logger.info("CodexClient state: \(oldValue) -> \(state)")
        }
    }

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    
    /// Buffer for accumulating partial lines from stdout.
    private var stdoutBuffer = Data()

    private var requestId = 0
    private var pendingRequests: [Int: CheckedContinuation<CodexJSON, Error>] = [:]

    private let eventContinuation: AsyncStream<CodexEvent>.Continuation
    nonisolated let events: AsyncStream<CodexEvent>

    private let logger = Logger(label: "devys.codex")
    
    /// Count of events yielded for debugging.
    private var eventsYielded = 0
    
    /// Count of lines read from stdout.
    private var linesRead = 0
    
    /// Count of messages sent.
    private var messagesSent = 0

    // MARK: - Initialization

    init() {
        var continuation: AsyncStream<CodexEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
        logger.info("CodexClient initialized")
    }

}

extension CodexClient {
    // MARK: - Lifecycle

    /// Starts the Codex App Server subprocess.
    func start(clientName: String = "devys", version: String = "1.0.0") async throws {
        logger.info("CodexClient.start() called - clientName: \(clientName), version: \(version)")
        
        guard state == .idle || state == .stopped else {
            logger.warning("CodexClient.start() rejected - already in state: \(state)")
            throw CodexError.alreadyRunning
        }

        state = .starting

        let codexPath = try resolveCodexPath()
        configureProcess(path: codexPath)
        configureArguments()
        configureEnvironment()
        let stderrPipe = configurePipes()
        configureHandlers(stderrPipe: stderrPipe)

        // Start process
        try runProcess()

        // Start reading events using callback-based approach
        logger.debug("Setting up stdout readability handler...")
        setupStdoutHandler()

        // Give the handler time to start
        logger.debug("Waiting 100ms for event reader to start...")
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Initialize handshake
        try await initializeHandshake(clientName: clientName, version: version)

        state = .ready
        logger.info("Codex App Server ready - waiting for commands...")
    }

    private func resolveCodexPath() throws -> String {
        do {
            let codexPath = try findCodexBinary()
            logger.info("Found Codex binary at: \(codexPath)")
            return codexPath
        } catch {
            logger.error("Failed to find Codex binary: \(error)")
            state = .error("Codex binary not found: \(error.localizedDescription)")
            throw error
        }
    }

    private func configureProcess(path: String) {
        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: path)
        process = newProcess
    }

    private func configureArguments() {
        var arguments = [
            "app-server",
            // Enable experimental features
            "--enable", "collab",
            "--enable", "child_agents_md"
        ]

        if let defaultModel = CodexConfiguration.getCurrentModel() {
            arguments.insert(contentsOf: ["-c", "model=\"\(defaultModel)\""], at: 1)
            logger.debug("Using configured model: \(defaultModel)")
        }

        logger.info("Codex arguments: \(arguments.joined(separator: " "))")
        process?.arguments = arguments
    }

    private func configureEnvironment() {
        var env = ProcessInfo.processInfo.environment
        let additionalPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        ]
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = (additionalPaths + [existingPath]).joined(separator: ":")

        logger.debug("OPENAI_API_KEY present: \(env["OPENAI_API_KEY"] != nil)")
        process?.environment = env
    }

    private func configurePipes() -> Pipe {
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process?.standardInput = stdinPipe
        process?.standardOutput = stdoutPipe
        process?.standardError = stderrPipe

        stdin = stdinPipe.fileHandleForWriting
        stdout = stdoutPipe.fileHandleForReading

        logger.debug("Pipes configured - stdin/stdout/stderr ready")
        return stderrPipe
    }

    private func configureHandlers(stderrPipe: Pipe) {
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                Task { [weak self] in
                    await self?.logStderr(str)
                }
            }
        }

        process?.terminationHandler = { [weak self] proc in
            Task { [weak self] in
                await self?.handleTermination(exitCode: proc.terminationStatus)
            }
        }
    }

    private func runProcess() throws {
        logger.info("Starting Codex process...")
        do {
            try process?.run()
            if let pid = process?.processIdentifier {
                logger.info("Codex process started successfully - PID: \(pid)")
            }
        } catch {
            logger.error("Failed to start Codex process: \(error)")
            state = .error("Failed to start: \(error.localizedDescription)")
            throw CodexError.processStartFailed(error.localizedDescription)
        }
    }

    private func initializeHandshake(clientName: String, version: String) async throws {
        logger.info("Sending initialize request...")
        let initResult = try await sendRequest(method: "initialize", params: [
            "clientInfo": [
                "name": clientName,
                "title": "Devys",
                "version": version
            ]
        ])
        logger.info("Codex initialized - response: \(initResult.value)")

        logger.debug("Sending initialized notification...")
        try await sendNotification(method: "initialized", params: [:])
    }

    /// Stops the Codex App Server.
    func stop() async {
        logger.info("CodexClient.stop() called - current state: \(state)")
        
        // Clear readability handlers first
        stdout?.readabilityHandler = nil
        stdoutBuffer.removeAll()
        
        if let process = process, process.isRunning {
            logger.info("Terminating Codex process PID: \(process.processIdentifier)")
            process.terminate()
        }
        process = nil
        stdin = nil
        stdout = nil
        state = .stopped
        eventContinuation.finish()
        logger.info("Codex stopped - sent \(messagesSent) messages, read \(linesRead) lines, yielded \(eventsYielded) events")
    }

    // MARK: - Thread Management

    /// Creates a new conversation thread.
    func startThread(
        cwd: String,
        model: String? = nil,
        configuration: AgentConfiguration = .default
    ) async throws -> CodexThread {
        logger.info("startThread() - cwd: \(cwd), model: \(model ?? "nil")")
        
        var params: [String: Any] = [
            "cwd": cwd,
            "sandbox": configuration.sandboxMode.rawValue,
            "approvalPolicy": configuration.approvalPolicy.rawValue
        ]
        if let model = model {
            params["model"] = model
        }
        if configuration.networkAccess {
            params["networkAccess"] = true
        }

        let result = try await sendRequest(method: "thread/start", params: params).value
        logger.debug("thread/start response: \(result)")

        guard let threadData = result["thread"] as? [String: Any] else {
            logger.error("thread/start response missing 'thread' key")
            throw CodexError.invalidResponse("Missing thread in response")
        }

        let thread = CodexThread(from: threadData)
        logger.info("Thread started: \(thread.id)")
        return thread
    }

    /// Resumes an existing thread.
    func resumeThread(id: String) async throws -> CodexThread {
        logger.info("resumeThread() - id: \(id)")
        
        let result = try await sendRequest(method: "thread/resume", params: ["threadId": id]).value
        logger.debug("thread/resume response: \(result)")

        guard let threadData = result["thread"] as? [String: Any] else {
            logger.error("thread/resume response missing 'thread' key")
            throw CodexError.invalidResponse("Missing thread in response")
        }

        let thread = CodexThread(from: threadData)
        logger.info("Thread resumed: \(thread.id)")
        return thread
    }

    /// Archives a thread.
    func archiveThread(id: String) async throws {
        logger.info("archiveThread() - id: \(id)")
        _ = try await sendRequest(method: "thread/archive", params: ["threadId": id])
        logger.info("Thread archived: \(id)")
    }

    // MARK: - Turn Management

    /// Starts a turn (sends user message).
    func startTurn(
        threadId: String,
        prompt: String,
        cwd: String,
        model: String? = nil,
        configuration: AgentConfiguration = .default
    ) async throws -> String {
        logger.info("startTurn() - threadId: \(threadId), prompt length: \(prompt.count) chars")
        
        // Input must be an array of input items
        let inputItems: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]

        // Build sandbox policy
        var sandboxPolicy: [String: Any] = [:]
        switch configuration.sandboxMode {
        case .readOnly:
            sandboxPolicy["type"] = "readOnly"
        case .workspaceWrite:
            sandboxPolicy["type"] = "workspaceWrite"
            sandboxPolicy["writableRoots"] = [cwd]
            sandboxPolicy["networkAccess"] = configuration.networkAccess
        case .dangerFullAccess:
            sandboxPolicy["type"] = "dangerFullAccess"
        }

        var params: [String: Any] = [
            "threadId": threadId,
            "input": inputItems,
            "cwd": cwd,
            "approvalPolicy": configuration.approvalPolicy.rawValue,
            "sandboxPolicy": sandboxPolicy
        ]

        if let model = model {
            params["model"] = model
        }

        let result = try await sendRequest(method: "turn/start", params: params).value
        logger.debug("turn/start response: \(result)")

        // Response may have turn.id or turnId
        var turnId = ""
        if let turn = result["turn"] as? [String: Any], let id = turn["id"] as? String {
            turnId = id
        } else {
            turnId = result["turnId"] as? String ?? ""
        }
        
        logger.info("Turn started: \(turnId)")
        return turnId
    }

    // MARK: - Approval Handling

    /// Responds to an approval request from Codex.
    func respondToApproval(
        requestId: Int,
        decision: ApprovalDecision,
        forSession: Bool = false
    ) async throws {
        var result: [String: Any] = ["decision": decision.rawValue]

        if forSession && decision == .accept {
            result["acceptSettings"] = ["forSession": true]
        }

        try await sendResponse(to: requestId, result: result)
    }

    /// Responds to a user input request (elicitation).
    func respondToUserInput(requestId: String, answers: [String]) async throws {
        let params: [String: Any] = [
            "requestId": requestId,
            "request_id": requestId,
            "response": [
                "answers": answers
            ]
        ]

        _ = try await sendRequest(method: "resolve_elicitation", params: params)
    }

    // MARK: - Skills

    /// Lists available skills.
    func listSkills(cwds: [String]) async throws -> CodexJSONArray {
        let result = try await sendRequest(method: "skills/list", params: [
            "cwds": cwds,
            "forceReload": false
        ]).value

        return CodexJSONArray(result["data"] as? [[String: Any]] ?? [])
    }

    // MARK: - JSON-RPC Communication

    private func sendRequest(method: String, params: [String: Any]) async throws -> CodexJSON {
        guard state == .ready || state == .starting else {
            logger.error("sendRequest(\(method)) failed - not ready, state: \(state)")
            throw CodexError.notReady
        }

        requestId += 1
        let id = requestId
        
        logger.debug("sendRequest() - id: \(id), method: \(method)")

        let message: [String: Any] = [
            "method": method,
            "id": id,
            "params": params
        ]

        try writeMessage(message)

        logger.debug("Waiting for response to request \(id)...")
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }

    private func sendNotification(method: String, params: [String: Any]) async throws {
        logger.debug("sendNotification() - method: \(method)")
        let message: [String: Any] = [
            "method": method,
            "params": params
        ]
        try writeMessage(message)
    }

    private func sendResponse(to requestId: Int, result: [String: Any]) async throws {
        logger.debug("sendResponse() - id: \(requestId)")
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "result": result
        ]
        try writeMessage(message)
    }

    private func writeMessage(_ message: [String: Any]) throws {
        guard let stdin = stdin else {
            logger.error("writeMessage failed - stdin is nil")
            throw CodexError.notReady
        }

        let data = try JSONSerialization.data(withJSONObject: message)
        var dataWithNewline = data
        dataWithNewline.append(contentsOf: "\n".utf8)
        
        messagesSent += 1
        if let jsonString = String(data: data, encoding: .utf8) {
            logger.debug("STDIN [\(messagesSent)] >>> \(jsonString.prefix(500))")
        }
        
        stdin.write(dataWithNewline)
    }

    // MARK: - Event Reading (Callback-based)
    
    /// Sets up callback-based reading from stdout.
    /// This is more reliable than async iteration for real-time streaming.
    private func setupStdoutHandler() {
        guard let stdout = stdout else {
            logger.error("setupStdoutHandler() - stdout is nil")
            return
        }
        
        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            
            if data.isEmpty {
                // EOF - process any remaining buffer
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
    private func handleStdoutData(_ data: Data) async {
        stdoutBuffer.append(data)
        
        // Process complete lines (split by newline)
        while let newlineIndex = stdoutBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = stdoutBuffer[..<newlineIndex]
            stdoutBuffer.removeSubrange(...newlineIndex)
            
            await processLine(lineData)
        }
    }
    
    /// Handles EOF on stdout.
    private func handleStdoutEOF() async {
        logger.info("Stdout EOF received")
        
        // Process any remaining data in buffer
        if !stdoutBuffer.isEmpty {
            await processLine(stdoutBuffer)
            stdoutBuffer.removeAll()
        }
        
        // Clear the handler
        stdout?.readabilityHandler = nil
    }
    
    /// Processes a single line of JSON from stdout.
    private func processLine(_ lineData: Data) async {
        linesRead += 1
        
        guard let line = String(data: lineData, encoding: .utf8) else {
            logger.warning("Line \(linesRead): Failed to decode as UTF-8")
            return
        }
        
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return }
        
        logger.debug("STDOUT [\(linesRead)] <<< \(trimmedLine.prefix(500))")
        
        guard let jsonData = trimmedLine.data(using: .utf8) else {
            logger.warning("Line \(linesRead): Failed to encode as UTF-8 data")
            return
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                logger.warning("Line \(linesRead): JSON parsed but not a dictionary")
                return
            }
            await handleMessage(json)
        } catch {
            logger.error("Line \(linesRead): Failed to parse JSON - \(error) - raw: \(trimmedLine.prefix(200))")
        }
    }

    private func handleMessage(_ json: [String: Any]) async {
        // Response to our request
        if let id = json["id"] as? Int, let continuation = pendingRequests.removeValue(forKey: id) {
            logger.debug("Received response for request \(id)")
            
            if let error = json["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? -1
                let message = error["message"] as? String ?? "Unknown error"
                logger.error("Request \(id) failed: [\(code)] \(message)")
                continuation.resume(throwing: CodexError.rpcError(code: code, message: message))
            } else if let result = json["result"] as? [String: Any] {
                logger.debug("Request \(id) succeeded")
                continuation.resume(returning: CodexJSON(result))
            } else {
                logger.debug("Request \(id) returned empty result")
                continuation.resume(returning: CodexJSON([:]))
            }
            return
        }

        // Notification or server request
        if let method = json["method"] as? String {
            let params = json["params"] as? [String: Any] ?? [:]
            let serverRequestId = json["id"] as? Int

            let event = CodexEvent.parse(method: method, params: params, requestId: serverRequestId)
            eventsYielded += 1
            logger.debug("Yielding event #\(eventsYielded): method=\(method)")
            eventContinuation.yield(event)
        } else {
            logger.warning("Received message with no 'id' response or 'method' notification: \(json.keys)")
        }
    }

    // MARK: - Helpers

    private func findCodexBinary() throws -> String {
        let paths = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        ]
        
        logger.debug("Searching for Codex binary in: \(paths)")

        for path in paths {
            let exists = FileManager.default.isExecutableFile(atPath: path)
            logger.debug("  \(path): \(exists ? "FOUND" : "not found")")
            if exists {
                return path
            }
        }

        // Try `which` as fallback
        logger.debug("Trying `which codex` as fallback...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["codex"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0,
           let data = try? pipe.fileHandleForReading.readToEnd(),
           let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            logger.debug("`which` found Codex at: \(path)")
            return path
        }

        logger.error("Codex binary not found in any location")
        throw CodexError.binaryNotFound
    }

    private func handleTermination(exitCode: Int32) {
        logger.info("Codex process terminated - exitCode: \(exitCode), previousState: \(state)")
        if exitCode != 0 && state == .ready {
            state = .error("Exited with code \(exitCode)")
            logger.error("Codex terminated unexpectedly with code: \(exitCode)")
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
