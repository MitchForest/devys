//
//  CodexProcess.swift
//  devys
//
//  Codex agent integration via JSON-RPC over stdio.
//  Spawns `codex app-server` and communicates via stdin/stdout.
//

import Foundation

/// Codex CLI process wrapper using JSON-RPC over stdio.
actor CodexProcess: ProcessProtocol {
    // MARK: - Properties
    
    let workspacePath: String
    private(set) var state: ProcessState = .disconnected
    
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    
    private var requestId = 0
    private var pendingRequests: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    
    private let eventContinuation: AsyncStream<ProcessEvent>.Continuation
    let events: AsyncStream<ProcessEvent>
    
    private var currentThreadId: String?
    
    // MARK: - Initialization
    
    init(workspacePath: String) {
        self.workspacePath = workspacePath
        
        var continuation: AsyncStream<ProcessEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }
    
    deinit {
        eventContinuation.finish()
    }
    
    // MARK: - Lifecycle
    
    func start() async throws {
        guard state != .connected else { return }
        
        state = .connecting
        
        // Get codex path from settings
        let codexPath = UserDefaults.standard.string(forKey: "codexPath") ?? "/usr/local/bin/codex"
        
        // Verify codex exists
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            state = .error("Codex not found at \(codexPath)")
            throw ProcessError(code: "CODEX_NOT_FOUND", message: "Codex CLI not found at \(codexPath)", recoverable: false)
        }
        
        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]
        process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
        
        // Set up pipes
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // Handle termination
        process.terminationHandler = { [weak self] _ in
            Task { [weak self] in
                await self?.handleTermination()
            }
        }
        
        do {
            try process.run()
        } catch {
            state = .error("Failed to start: \(error.localizedDescription)")
            throw ProcessError(code: "START_FAILED", message: error.localizedDescription, recoverable: false)
        }
        
        self.process = process
        self.stdin = stdinPipe.fileHandleForWriting
        self.stdout = stdoutPipe.fileHandleForReading
        
        // Start reading stdout in background
        Task { await readLoop() }
        
        // Start reading stderr for debugging
        Task { await readStderr(stderrPipe.fileHandleForReading) }
        
        state = .connected
        eventContinuation.yield(.connected)
    }
    
    func stop() async {
        process?.terminate()
        process = nil
        stdin = nil
        stdout = nil
        state = .disconnected
        eventContinuation.yield(.disconnected)
    }
    
    private func handleTermination() {
        state = .disconnected
        eventContinuation.yield(.disconnected)
        
        // Fail any pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: ProcessError.processTerminated)
        }
        pendingRequests.removeAll()
    }
    
    // MARK: - Message Sending
    
    func sendMessage(_ content: String, threadId: String?) async throws {
        var params: [String: Any] = ["content": content]
        if let threadId {
            params["thread_id"] = threadId
        }
        
        // Send as notification (no response expected for message sending)
        try await notify(method: "thread/send", params: params)
    }
    
    func listThreads() async throws -> [ProcessThreadInfo] {
        let response = try await request(method: "thread/list", params: [:])
        
        guard let result = response.result as? [[String: Any]] else {
            return []
        }
        
        return result.compactMap { dict -> ProcessThreadInfo? in
            guard let id = dict["id"] as? String else { return nil }
            return ProcessThreadInfo(
                id: id,
                title: dict["title"] as? String,
                lastMessageAt: parseDate(dict["last_message_at"]) ?? Date(),
                messageCount: dict["message_count"] as? Int ?? 0
            )
        }
    }
    
    func resumeThread(_ id: String) async throws {
        currentThreadId = id
        _ = try await request(method: "thread/resume", params: ["id": id])
    }
    
    func archiveThread(_ id: String) async throws {
        _ = try await request(method: "thread/archive", params: ["id": id])
    }
    
    func respondToApproval(_ id: String, approved: Bool) async throws {
        _ = try await request(method: "approval/respond", params: [
            "id": id,
            "approved": approved
        ])
    }
    
    // MARK: - JSON-RPC
    
    private func request(method: String, params: [String: Any]) async throws -> JSONRPCResponse {
        guard state == .connected, let stdin else {
            throw ProcessError.processNotStarted
        }
        
        requestId += 1
        let id = requestId
        
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        
        let data = try JSONSerialization.data(withJSONObject: request)
        
        // Write request
        stdin.write(data)
        stdin.write("\n".data(using: .utf8)!)
        
        // Wait for response
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }
    
    private func notify(method: String, params: [String: Any]) async throws {
        guard state == .connected, let stdin else {
            throw ProcessError.processNotStarted
        }
        
        let notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        
        let data = try JSONSerialization.data(withJSONObject: notification)
        stdin.write(data)
        stdin.write("\n".data(using: .utf8)!)
    }
    
    // MARK: - Reading
    
    private func readLoop() async {
        guard let stdout else { return }
        
        var buffer = Data()
        
        while state == .connected || state == .connecting {
            do {
                let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    DispatchQueue.global().async {
                        let data = stdout.availableData
                        if data.isEmpty {
                            continuation.resume(throwing: ProcessError.processTerminated)
                        } else {
                            continuation.resume(returning: data)
                        }
                    }
                }
                
                buffer.append(chunk)
                
                // Process complete lines
                while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = buffer[..<newlineIndex]
                    buffer = Data(buffer[(newlineIndex + 1)...])
                    
                    if !lineData.isEmpty {
                        await parseMessage(Data(lineData))
                    }
                }
            } catch {
                break
            }
        }
    }
    
    private func readStderr(_ handle: FileHandle) async {
        // Read stderr for debugging but don't block
        DispatchQueue.global().async {
            while let data = try? handle.availableData, !data.isEmpty {
                if let str = String(data: data, encoding: .utf8) {
                    print("[Codex stderr] \(str)")
                }
            }
        }
    }
    
    private func parseMessage(_ data: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        // Check if this is a response (has id)
        if let id = json["id"] as? Int {
            let response = JSONRPCResponse(
                id: id,
                result: json["result"],
                error: json["error"] as? [String: Any]
            )
            
            if let continuation = pendingRequests.removeValue(forKey: id) {
                if response.error != nil {
                    continuation.resume(throwing: ProcessError(
                        code: response.error?["code"] as? String ?? "UNKNOWN",
                        message: response.error?["message"] as? String ?? "Unknown error"
                    ))
                } else {
                    continuation.resume(returning: response)
                }
            }
            return
        }
        
        // This is a notification/event
        guard let method = json["method"] as? String,
              let params = json["params"] as? [String: Any] else {
            return
        }
        
        await handleEvent(method: method, params: params)
    }
    
    private func handleEvent(method: String, params: [String: Any]) async {
        switch method {
        case "message":
            if let role = params["role"] as? String,
               let content = params["content"] as? String {
                let message = ProcessMessage(
                    id: params["id"] as? String ?? UUID().uuidString,
                    role: role,
                    content: content
                )
                eventContinuation.yield(.message(message))
            }
            
        case "reasoning", "thinking":
            if let content = params["content"] as? String {
                eventContinuation.yield(.reasoning(content))
            }
            
        case "tool_call", "tool_use":
            let toolCall = ProcessToolCall(
                id: params["id"] as? String ?? UUID().uuidString,
                name: params["name"] as? String ?? params["tool"] as? String ?? "unknown",
                arguments: parseArguments(params["arguments"] ?? params["input"])
            )
            eventContinuation.yield(.toolCall(toolCall))
            
        case "tool_result":
            if let id = params["id"] as? String,
               let result = params["result"] as? String {
                let success = params["success"] as? Bool ?? true
                eventContinuation.yield(.toolResult(id: id, result: result, success: success))
            }
            
        case "diff":
            if let path = params["path"] as? String,
               let content = params["content"] as? String {
                let diff = ProcessFileDiff(
                    path: path,
                    content: content,
                    linesAdded: params["lines_added"] as? Int ?? 0,
                    linesRemoved: params["lines_removed"] as? Int ?? 0
                )
                eventContinuation.yield(.diff(diff))
            }
            
        case "approval", "approval_required":
            if let id = params["id"] as? String,
               let description = params["description"] as? String {
                let toolName = params["tool"] as? String ?? params["tool_name"] as? String ?? "action"
                eventContinuation.yield(.approvalRequired(id: id, description: description, toolName: toolName))
            }
            
        case "usage":
            if let input = params["input_tokens"] as? Int,
               let output = params["output_tokens"] as? Int {
                eventContinuation.yield(.usage(inputTokens: input, outputTokens: output))
            }
            
        case "error":
            let error = ProcessError(
                code: params["code"] as? String ?? "UNKNOWN",
                message: params["message"] as? String ?? "Unknown error"
            )
            eventContinuation.yield(.error(error))
            
        case "turn_complete", "done":
            eventContinuation.yield(.turnComplete)
            
        default:
            print("[Codex] Unknown event: \(method)")
        }
    }
    
    // MARK: - Helpers
    
    private func parseArguments(_ value: Any?) -> [String: String] {
        guard let dict = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, val) in dict {
            result[key] = String(describing: val)
        }
        return result
    }
    
    private func parseDate(_ value: Any?) -> Date? {
        if let string = value as? String {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: string)
        }
        if let timestamp = value as? Double {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }
}

// MARK: - JSON-RPC Response

struct JSONRPCResponse {
    let id: Int
    let result: Any?
    let error: [String: Any]?
}
