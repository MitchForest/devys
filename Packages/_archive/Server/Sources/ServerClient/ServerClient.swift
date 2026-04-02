import Foundation
import ServerProtocol

public enum ServerClientError: Error, Sendable {
    case invalidResponse
    case badStatus(Int)
    case emptyLine
    case invalidURL
}

public actor ServerClient {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func health(baseURL: URL) async throws -> HealthResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "health")
        return try await requestJSON(url: url, method: "GET", body: Optional<Data>.none)
    }

    public func capabilities(baseURL: URL) async throws -> ServerCapabilitiesResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "capabilities")
        return try await requestJSON(url: url, method: "GET", body: Optional<Data>.none)
    }

    public func createPairingChallenge(
        baseURL: URL,
        deviceName: String? = nil
    ) async throws -> PairingChallengeResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "pairing/challenge")
        let body = try ServerJSONCoding.makeEncoder().encode(PairingChallengeRequest(deviceName: deviceName))
        return try await requestJSON(url: url, method: "POST", body: body)
    }

    public func exchangePairing(
        baseURL: URL,
        challengeID: String,
        setupCode: String,
        deviceName: String
    ) async throws -> PairingExchangeResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "pairing/exchange")
        let body = try ServerJSONCoding.makeEncoder().encode(
            PairingExchangeRequest(challengeID: challengeID, setupCode: setupCode, deviceName: deviceName)
        )
        return try await requestJSON(url: url, method: "POST", body: body)
    }

    public func listPairings(baseURL: URL) async throws -> ListPairingsResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "pairings")
        return try await requestJSON(url: url, method: "GET", body: Optional<Data>.none)
    }

    public func rotatePairing(baseURL: URL, pairingID: String) async throws -> RotatePairingResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "pairings/\(pairingID)/rotate")
        return try await requestJSON(url: url, method: "POST", body: Optional<Data>.none)
    }

    public func revokePairing(baseURL: URL, pairingID: String) async throws -> RevokePairingResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "pairings/\(pairingID)/revoke")
        return try await requestJSON(url: url, method: "POST", body: Optional<Data>.none)
    }

    public func listCommandProfiles(baseURL: URL) async throws -> ListCommandProfilesResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "profiles")
        return try await requestJSON(url: url, method: "GET", body: Optional<Data>.none)
    }

    public func saveCommandProfile(
        baseURL: URL,
        profile: CommandProfile
    ) async throws -> SaveCommandProfileResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "profiles")
        let body = try ServerJSONCoding.makeEncoder().encode(SaveCommandProfileRequest(profile: profile))
        return try await requestJSON(url: url, method: "POST", body: body)
    }

    public func validateCommandProfile(
        baseURL: URL,
        profile: CommandProfile
    ) async throws -> ValidateCommandProfileResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "profiles/validate")
        let body = try ServerJSONCoding.makeEncoder().encode(ValidateCommandProfileRequest(profile: profile))
        return try await requestJSON(url: url, method: "POST", body: body)
    }

    public func deleteCommandProfile(
        baseURL: URL,
        profileID: String
    ) async throws -> DeleteCommandProfileResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "profiles/delete")
        let body = try ServerJSONCoding.makeEncoder().encode(DeleteCommandProfileRequest(id: profileID))
        return try await requestJSON(url: url, method: "POST", body: body)
    }

    public func stream(baseURL: URL) -> AsyncThrowingStream<StreamEventEnvelope, Error> {
        let url = Self.endpoint(baseURL: baseURL, path: "stream")

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ServerClientError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw ServerClientError.badStatus(http.statusCode)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            break
                        }
                        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            continue
                        }
                        continuation.yield(try Self.decodeEventLine(line))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public static func decodeEventLine(_ line: String) throws -> StreamEventEnvelope {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServerClientError.emptyLine
        }
        let data = Data(trimmed.utf8)
        return try ServerJSONCoding.makeDecoder().decode(StreamEventEnvelope.self, from: data)
    }

    public func createSession(
        baseURL: URL,
        workspacePath: String? = nil
    ) async throws -> CreateSessionResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "sessions")
        let body = try ServerJSONCoding.makeEncoder().encode(CreateSessionRequest(workspacePath: workspacePath))
        return try await requestJSON(url: url, method: "POST", body: body)
    }

    public func listSessions(baseURL: URL) async throws -> ListSessionsResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "sessions")
        return try await requestJSON(url: url, method: "GET", body: Optional<Data>.none)
    }

    public func runSession(
        baseURL: URL,
        sessionID: String,
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> RunSessionResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "sessions/\(sessionID)/run")
        let body = try ServerJSONCoding.makeEncoder().encode(
            RunSessionRequest(
                command: command,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
        )
        return try await requestJSON(url: url, method: "POST", body: body)
    }

    public func stopSession(baseURL: URL, sessionID: String) async throws -> StopSessionResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "sessions/\(sessionID)/stop")
        return try await requestJSON(url: url, method: "POST", body: Optional<Data>.none)
    }

    public func terminalAttach(
        baseURL: URL,
        sessionID: String,
        cols: Int,
        rows: Int,
        terminalID: String? = nil,
        resumeCursor: UInt64? = nil
    ) async throws -> TerminalAttachResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "sessions/\(sessionID)/terminal/attach")
        let body = try ServerJSONCoding.makeEncoder().encode(
            TerminalAttachRequest(
                cols: cols,
                rows: rows,
                terminalID: terminalID,
                resumeCursor: resumeCursor
            )
        )
        return try await requestJSON(url: url, method: "POST", body: body)
    }

    public func terminalInputBytes(
        baseURL: URL,
        sessionID: String,
        bytesBase64: String,
        source: TerminalInputSource? = nil
    ) async throws -> TerminalInputBytesResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "sessions/\(sessionID)/terminal/input")
        let body = try ServerJSONCoding.makeEncoder().encode(
            TerminalInputBytesRequest(bytesBase64: bytesBase64, source: source)
        )
        return try await requestJSON(url: url, method: "POST", body: body)
    }

    public func terminalInputBytes(
        baseURL: URL,
        sessionID: String,
        data: Data,
        source: TerminalInputSource? = nil
    ) async throws -> TerminalInputBytesResponse {
        try await terminalInputBytes(
            baseURL: baseURL,
            sessionID: sessionID,
            bytesBase64: data.base64EncodedString(),
            source: source
        )
    }

    public func terminalResize(
        baseURL: URL,
        sessionID: String,
        cols: Int,
        rows: Int,
        source: TerminalResizeSource? = nil
    ) async throws -> TerminalResizeResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "sessions/\(sessionID)/terminal/resize")
        let body = try ServerJSONCoding.makeEncoder().encode(
            TerminalResizeRequest(cols: cols, rows: rows, source: source)
        )
        return try await requestJSON(url: url, method: "POST", body: body)
    }

    public func terminalEvents(
        baseURL: URL,
        sessionID: String,
        cursor: UInt64
    ) async throws -> TerminalEventsResponse {
        let base = Self.endpoint(baseURL: baseURL, path: "sessions/\(sessionID)/terminal/events")
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw ServerClientError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "cursor", value: String(cursor))]
        guard let url = components.url else {
            throw ServerClientError.invalidURL
        }
        return try await requestJSON(url: url, method: "GET", body: Optional<Data>.none)
    }

    static func endpoint(baseURL: URL, path: String) -> URL {
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appending(path: trimmedPath)
    }

    func requestJSON<Response: Decodable>(
        url: URL,
        method: String,
        body: Data?,
        headers: [String: String] = [:]
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServerClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ServerClientError.badStatus(http.statusCode)
        }
        return try ServerJSONCoding.makeDecoder().decode(Response.self, from: data)
    }
}
