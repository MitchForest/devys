import Foundation
import Observation
import ServerClient
import ServerProtocol

@MainActor
@Observable
final class MacClientConnectionStore {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    var serverURLText = UserDefaults.standard.string(
        forKey: ConversationConnectionDefaults.serverURLKey
    ) ?? "http://100.64.0.1:8787" {
        didSet {
            UserDefaults.standard.set(serverURLText, forKey: ConversationConnectionDefaults.serverURLKey)
        }
    }
    var chatAuthTokenText = UserDefaults.standard.string(
        forKey: ConversationConnectionDefaults.authTokenKey
    ) ?? "" {
        didSet {
            UserDefaults.standard.set(chatAuthTokenText, forKey: ConversationConnectionDefaults.authTokenKey)
        }
    }
    var state: ConnectionState = .disconnected
    var health: HealthResponse?
    var events: [StreamEventEnvelope] = []
    var terminalSession = RemoteTerminalSession()
    var terminalInputText = ""

    private let client = ServerClient()
    private var streamTask: Task<Void, Never>?
    private var connectedBaseURL: URL?

    func connect() {
        let trimmedURL = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        serverURLText = trimmedURL
        guard let baseURL = URL(string: trimmedURL) else {
            state = .failed("Invalid server URL")
            return
        }
        state = .connecting
        health = nil
        events = []
        connectedBaseURL = nil
        streamTask?.cancel()
        streamTask = nil

        Task {
            do {
                let health = try await client.health(baseURL: baseURL)
                self.health = health
                self.state = .connected
                self.connectedBaseURL = baseURL
                self.startStream(baseURL: baseURL)
            } catch {
                self.state = .failed("Connect failed: \(error.localizedDescription)")
            }
        }
    }

    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        connectedBaseURL = nil
        terminalSession.disconnect()
        state = .disconnected
    }

    func connectTerminal(cols: Int = 120, rows: Int = 40) {
        guard let baseURL = connectedBaseURL else {
            state = .failed("Connect to mac-server first")
            return
        }

        Task {
            do {
                try await terminalSession.connect(baseURL: baseURL, cols: cols, rows: rows)
            } catch {
                state = .failed("Terminal attach failed: \(error.localizedDescription)")
            }
        }
    }

    func reconnectTerminal() {
        Task {
            do {
                try await terminalSession.reconnect()
            } catch {
                state = .failed("Terminal reconnect failed: \(error.localizedDescription)")
            }
        }
    }

    func disconnectTerminal() {
        terminalSession.disconnect()
    }

    func clearTerminalOutput() {
        terminalSession.clearOutputPreview()
    }

    func sendTerminalInput() {
        let text = terminalInputText.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return }
        terminalInputText = ""

        Task {
            do {
                try await terminalSession.sendText("\(text)\n")
            } catch {
                state = .failed("Terminal input failed: \(error.localizedDescription)")
            }
        }
    }

    private func startStream(baseURL: URL) {
        streamTask?.cancel()
        streamTask = Task {
            do {
                let stream = await client.stream(baseURL: baseURL)
                for try await event in stream {
                    events.insert(event, at: 0)
                    if events.count > 200 {
                        events.removeLast(events.count - 200)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    state = .failed("Stream failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
