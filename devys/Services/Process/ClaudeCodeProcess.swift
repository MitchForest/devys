//
//  ClaudeCodeProcess.swift
//  devys
//
//  Claude Code agent integration via stream-json over stdio.
//  Spawns `claude --output-format stream-json` and parses events.
//

import Foundation

/// Claude Code CLI process wrapper using stream-json over stdio.
actor ClaudeCodeProcess: ProcessProtocol {
    // MARK: - Properties
    
    let workspacePath: String
    private(set) var state: ProcessState = .disconnected
    
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    
    private let eventContinuation: AsyncStream<ProcessEvent>.Continuation
    let events: AsyncStream<ProcessEvent>
    
    private var currentThreadId: String?
    private var pendingApprovals: [String: CheckedContinuation<Bool, Never>] = [:]
    
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
        
        // Get claude path from settings
        let claudePath = UserDefaults.standard.string(forKey: "claudePath") ?? "/usr/local/bin/claude"
        
        // Verify claude exists
        guard FileManager.default.isExecutableFile(atPath: claudePath) else {
            state = .error("Claude CLI not found at \(claudePath)")
            throw ProcessError(code: "CLAUDE_NOT_FOUND", message: "Claude CLI not found at \(claudePath)", recoverable: false)
        }
        
        // Note: Claude Code doesn't have a persistent server mode like Codex.
        // Each conversation starts a new process. For now, we'll just mark as connected.
        // The actual process is spawned per-message.
        
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
    
    // MARK: - Message Sending
    
    func sendMessage(_ content: String, threadId: String?) async throws {
        guard state == .connected else {
            throw ProcessError.processNotStarted
        }
        
        // Get claude path from settings
        let claudePath = UserDefaults.standard.string(forKey: "claudePath") ?? "/usr/local/bin/claude"
        
        // Create process for this message
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        
        // Build arguments
        var args = ["--output-format", "stream-json"]
        
        // Add continue flag if resuming a thread
        if let threadId, !threadId.isEmpty {
            args.append("--continue")
            args.append(threadId)
        }
        
        // Add the prompt
        args.append("--print")
        args.append(content)
        
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
        
        // Set up pipes
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        self.process = process
        self.stdin = stdinPipe.fileHandleForWriting
        self.stdout = stdoutPipe.fileHandleForReading
        
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
        
        // Start reading stdout
        Task { await readLoop(stdoutPipe.fileHandleForReading) }
        
        // Read stderr for debugging
        Task { await readStderr(stderrPipe.fileHandleForReading) }
    }
    
    func listThreads() async throws -> [ProcessThreadInfo] {
        // Claude Code stores threads in ~/.claude/projects/
        // For now, return empty - thread management is handled by SwiftData
        return []
    }
    
    func resumeThread(_ id: String) async throws {
        currentThreadId = id
    }
    
    func archiveThread(_ id: String) async throws {
        // Claude doesn't have archive functionality
    }
    
    func respondToApproval(_ id: String, approved: Bool) async throws {
        // Send response via stdin
        guard let stdin else {
            throw ProcessError.processNotStarted
        }
        
        let response = approved ? "y\n" : "n\n"
        if let data = response.data(using: .utf8) {
            stdin.write(data)
        }
        
        // Resume any waiting continuation
        if let continuation = pendingApprovals.removeValue(forKey: id) {
            continuation.resume(returning: approved)
        }
    }
    
    // MARK: - Reading
    
    private func readLoop(_ handle: FileHandle) async {
        var buffer = Data()
        
        while process?.isRunning == true {
            do {
                let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    DispatchQueue.global().async {
                        let data = handle.availableData
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
                        await parseStreamEvent(Data(lineData))
                    }
                }
            } catch {
                break
            }
        }
        
        eventContinuation.yield(.turnComplete)
    }
    
    private func readStderr(_ handle: FileHandle) async {
        DispatchQueue.global().async {
            while let data = try? handle.availableData, !data.isEmpty {
                if let str = String(data: data, encoding: .utf8) {
                    print("[Claude stderr] \(str)")
                }
            }
        }
    }
    
    private func handleTermination() {
        eventContinuation.yield(.turnComplete)
        eventContinuation.yield(.disconnected)
        
        // Fail any pending approvals
        for (_, continuation) in pendingApprovals {
            continuation.resume(returning: false)
        }
        pendingApprovals.removeAll()
        
        process = nil
    }
    
    // MARK: - Event Parsing
    
    /// Parse a stream-json event line from Claude Code
    private func parseStreamEvent(_ data: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        guard let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "assistant", "text":
            if let text = json["text"] as? String ?? (json["content"] as? [[String: Any]])?.first?["text"] as? String {
                let message = ProcessMessage(role: "assistant", content: text)
                eventContinuation.yield(.message(message))
            }
            
        case "content_block_start":
            // Start of a content block - might be text or tool use
            if let contentBlock = json["content_block"] as? [String: Any],
               let blockType = contentBlock["type"] as? String {
                if blockType == "thinking", let text = contentBlock["thinking"] as? String {
                    eventContinuation.yield(.reasoning(text))
                }
            }
            
        case "content_block_delta":
            // Streaming delta
            if let delta = json["delta"] as? [String: Any] {
                if let text = delta["text"] as? String {
                    let message = ProcessMessage(role: "assistant", content: text)
                    eventContinuation.yield(.message(message))
                } else if let thinking = delta["thinking"] as? String {
                    eventContinuation.yield(.reasoning(thinking))
                }
            }
            
        case "tool_use", "tool_use_block":
            let toolCall = ProcessToolCall(
                id: json["id"] as? String ?? UUID().uuidString,
                name: json["name"] as? String ?? "unknown",
                arguments: parseToolInput(json["input"])
            )
            eventContinuation.yield(.toolCall(toolCall))
            
        case "tool_result":
            if let toolUseId = json["tool_use_id"] as? String,
               let content = json["content"] as? String {
                let success = !(json["is_error"] as? Bool ?? false)
                eventContinuation.yield(.toolResult(id: toolUseId, result: content, success: success))
            }
            
        case "input_request":
            // Claude is asking for approval
            let id = json["request_id"] as? String ?? UUID().uuidString
            let description = json["message"] as? String ?? "Action requires approval"
            eventContinuation.yield(.approvalRequired(id: id, description: description, toolName: "action"))
            
        case "result":
            // Final result
            if let result = json["result"] as? String {
                let message = ProcessMessage(role: "assistant", content: result)
                eventContinuation.yield(.message(message))
            }
            
            // Extract session ID for thread continuation
            if let sessionId = json["session_id"] as? String {
                currentThreadId = sessionId
            }
            
            // Extract usage if available
            if let usage = json["usage"] as? [String: Any] {
                let input = usage["input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                eventContinuation.yield(.usage(inputTokens: input, outputTokens: output))
            }
            
            eventContinuation.yield(.turnComplete)
            
        case "error":
            let error = ProcessError(
                code: json["error_code"] as? String ?? "UNKNOWN",
                message: json["message"] as? String ?? json["error"] as? String ?? "Unknown error"
            )
            eventContinuation.yield(.error(error))
            
        case "system":
            // System message - could be initialization
            if let message = json["message"] as? String {
                let msg = ProcessMessage(role: "system", content: message)
                eventContinuation.yield(.message(msg))
            }
            
        default:
            print("[Claude] Unknown event type: \(type)")
        }
    }
    
    private func parseToolInput(_ input: Any?) -> [String: String] {
        guard let dict = input as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in dict {
            result[key] = String(describing: value)
        }
        return result
    }
}
