public import Foundation

public enum DevysHTTPError: Error, Equatable, Sendable {
    /// The session is missing, expired or revoked; the device must sign in again.
    case unauthorized
    case rejected(status: Int, message: String)
    case unreachable(String)
    case invalidResponse
}

/// The Devys HTTP API as the native clients use it. One request shape:
/// bearer session, JSON in and out, typed failures.
public struct DevysHTTPClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport

    public init(transport: @escaping Transport) {
        self.transport = transport
    }

    public static let live = DevysHTTPClient { request in
        try await URLSession.shared.data(for: request)
    }

    public func account(_ session: DeviceSession) async throws -> Account {
        try await send(authorized(session, path: "api/me"))
    }

    /// Changes the name the signed-in person goes by (`PUT /api/me`).
    public func rename(_ session: DeviceSession, _ name: String) async throws -> Account {
        struct Body: Encodable {
            let displayName: String
            enum CodingKeys: String, CodingKey { case displayName = "display_name" }
        }
        return try await send(json(session, path: "api/me", method: "PUT", body: Body(displayName: name)))
    }

    public func business(_ session: DeviceSession, id: String) async throws -> BusinessDetail {
        try await send(authorized(session, path: "api/businesses/\(id)"))
    }

    /// Creates a business owned by the signed-in person: a Chief of Staff plus the starting team.
    public func createBusiness(_ session: DeviceSession, _ business: NewBusiness) async throws -> Business {
        struct Created: Decodable { let business: Business }
        let created: Created = try await send(json(session, path: "api/businesses", method: "POST", body: business))
        return created.business
    }

    public func status(_ session: DeviceSession, _ scope: EmployeeScope) async throws -> EmployeeStatus {
        try await send(authorized(session, path: "\(scope.path)/status"))
    }

    public func models(_ session: DeviceSession) async throws -> ModelCatalog {
        try await send(authorized(session, path: "api/models"))
    }

    /// Changes the model an employee thinks with; returns the model the server saved.
    public func setModel(_ session: DeviceSession, _ scope: EmployeeScope, model: String) async throws -> String {
        struct Body: Codable { let model: String }
        let saved: Body = try await send(json(session, path: "\(scope.path)/model", method: "PUT", body: Body(model: model)))
        return saved.model
    }

    public func stop(_ session: DeviceSession, _ scope: EmployeeScope) async throws -> Bool {
        struct Stopped: Decodable { let stopped: Bool }
        let stopped: Stopped = try await send(authorized(session, path: "\(scope.path)/stop", method: "POST"))
        return stopped.stopped
    }

    public func access(_ session: DeviceSession, _ scope: EmployeeScope) async throws -> AccessList {
        try await send(authorized(session, path: "\(scope.path)/access"))
    }

    /// Grants a capability, replacing any grant the employee holds for it.
    public func grant(_ session: DeviceSession, _ scope: EmployeeScope, capability: String, mode: AccessMode) async throws {
        struct Body: Encodable { let capability: String; let mode: AccessMode }
        _ = try await raw(json(session, path: "\(scope.path)/access", method: "POST", body: Body(capability: capability, mode: mode)))
    }

    public func revoke(_ session: DeviceSession, _ scope: EmployeeScope, grantID: String) async throws {
        _ = try await raw(authorized(session, path: "\(scope.path)/access/\(grantID)/revoke", method: "POST"))
    }

    /// Pausing also stops work already running; resuming lets the employee act again.
    public func setPaused(_ session: DeviceSession, _ scope: EmployeeScope, paused: Bool) async throws {
        _ = try await raw(authorized(session, path: "\(scope.path)/\(paused ? "pause" : "resume")", method: "POST"))
    }

    public func work(_ session: DeviceSession, businessID: String) async throws -> [WorkItem] {
        struct Page: Decodable {
            let workItems: [WorkItem]
            enum CodingKeys: String, CodingKey { case workItems = "work_items" }
        }
        let page: Page = try await send(authorized(session, path: "api/businesses/\(businessID)/work"))
        return page.workItems
    }

    /// Creates a work item for an employee, in a project when one is given.
    public func createWorkItem(_ session: DeviceSession, businessID: String, _ newItem: NewWorkItem) async throws -> WorkItem {
        try await send(json(session, path: "api/businesses/\(businessID)/work", method: "POST", body: newItem))
    }

    /// Changes a work item at the revision the caller saw; a stale revision is rejected with 409.
    public func updateWorkItem(_ session: DeviceSession, businessID: String, id: String, _ change: WorkItemChange) async throws -> WorkItem {
        try await send(json(session, path: "api/businesses/\(businessID)/work/\(id)", method: "POST", body: change))
    }

    /// Takes the work from its employee, or hands it back.
    public func setTakeover(_ session: DeviceSession, businessID: String, id: String, takeOver: Bool) async throws {
        _ = try await raw(authorized(
            session,
            path: "api/businesses/\(businessID)/work/\(id)/\(takeOver ? "takeover" : "release")",
            method: "POST"
        ))
    }

    /// Starts a plan that waits for the owner: its employee takes it now. 409 once it has started.
    public func startWorkItem(_ session: DeviceSession, businessID: String, id: String) async throws -> WorkItem {
        try await send(authorized(session, path: "api/businesses/\(businessID)/work/\(id)/start", method: "POST"))
    }

    /// One work item's requests with their answers. Pending ones across the business are Home's.
    public func decisions(_ session: DeviceSession, businessID: String, workItemID: String) async throws -> [Decision] {
        struct Page: Decodable { let decisions: [Decision] }
        var request = authorized(session, path: "api/businesses/\(businessID)/decisions")
        request.url?.append(queryItems: [URLQueryItem(name: "work_item", value: workItemID)])
        let page: Page = try await send(request)
        return page.decisions
    }

    public func answer(_ session: DeviceSession, businessID: String, decisionID: String, approve: Bool) async throws {
        _ = try await raw(authorized(
            session,
            path: "api/businesses/\(businessID)/decisions/\(decisionID)/\(approve ? "approve" : "reject")",
            method: "POST"
        ))
    }

    /// Answers a file request with the file the owner chose; the server puts it in the business folder.
    public func sendFile(_ session: DeviceSession, businessID: String, decisionID: String, _ file: ChosenFile) async throws {
        var request = authorized(session, path: "api/businesses/\(businessID)/decisions/\(decisionID)/file", method: "POST")
        request.url?.append(queryItems: [URLQueryItem(name: "name", value: file.name)])
        request.setValue(file.type, forHTTPHeaderField: "content-type")
        request.httpBody = file.data
        _ = try await raw(request)
    }

    /// A saved text artifact's whole contents, such as an employee's HTML page.
    public func artifactText(_ session: DeviceSession, businessID: String, artifactID: String) async throws -> String {
        let data = try await raw(authorized(session, path: "api/businesses/\(businessID)/artifacts/\(artifactID)"))
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Business-wide memory.
    public func memory(_ session: DeviceSession, businessID: String) async throws -> [MemoryClaim] {
        let page: MemoryPage = try await send(authorized(session, path: "api/businesses/\(businessID)/memory"))
        return page.items
    }

    public func react(_ session: DeviceSession, _ scope: EmployeeScope, _ reaction: Reaction) async throws {
        _ = try await raw(json(session, path: "\(scope.path)/reactions", method: "POST", body: reaction))
    }

    /// The signed-in person's profile photo, or nil when none is set.
    public func profilePhoto(_ session: DeviceSession) async throws -> Data? {
        do {
            return try await raw(authorized(session, path: "api/profile/photo"))
        } catch DevysHTTPError.rejected(status: 404, _) {
            return nil
        }
    }

    public func uploadProfilePhoto(_ session: DeviceSession, jpeg: Data) async throws {
        var request = authorized(session, path: "api/profile/photo", method: "PUT")
        request.setValue("image/jpeg", forHTTPHeaderField: "content-type")
        request.httpBody = jpeg
        _ = try await raw(request)
    }

    public func removeProfilePhoto(_ session: DeviceSession) async throws {
        _ = try await raw(authorized(session, path: "api/profile/photo", method: "DELETE"))
    }

    /// Sets a Face or emoji look, or nil for the default.
    public func setLook(_ session: DeviceSession, path: String, look: Look?) async throws {
        struct Body: Encodable {
            let look: Look?
            // nil must reach the server as null: it means "restore the default".
            func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(["look": look])
            }
        }
        _ = try await raw(json(session, path: "\(path)/look", method: "POST", body: Body(look: look)))
    }

    public func uploadLookPhoto(_ session: DeviceSession, path: String, jpeg: Data) async throws {
        var request = authorized(session, path: "\(path)/look/photo", method: "PUT")
        request.setValue("image/jpeg", forHTTPHeaderField: "content-type")
        request.httpBody = jpeg
        _ = try await raw(request)
    }

    public func lookPhoto(_ session: DeviceSession, path: String) async throws -> Data? {
        do {
            return try await raw(authorized(session, path: "\(path)/look/photo"))
        } catch DevysHTTPError.rejected(status: 404, _) {
            return nil
        }
    }

    public func signOut(_ session: DeviceSession) async throws {
        struct SignedOut: Decodable {
            let signedOut: Bool
            enum CodingKeys: String, CodingKey { case signedOut = "signed_out" }
        }
        let _: SignedOut = try await send(authorized(session, path: "api/logout", method: "POST"))
    }

    func json(_ session: DeviceSession, path: String, method: String, body: some Encodable) throws -> URLRequest {
        try withJSON(authorized(session, path: path, method: method), body)
    }

    /// The request with a JSON body.
    func withJSON(_ request: URLRequest, _ body: some Encodable) throws -> URLRequest {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try Wire.encoder().encode(body)
        return request
    }

    func authorized(_ session: DeviceSession, path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: session.server.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "authorization")
        return request
    }

    func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await raw(request)
        do {
            return try Wire.decode(Response.self, from: data)
        } catch let error as DevysHTTPError {
            throw error
        } catch {
            throw DevysHTTPError.invalidResponse
        }
    }

    func raw(_ request: URLRequest) async throws -> Data {
        try await response(request).data
    }

    /// The body and the response, for callers that read headers.
    func response(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            // A view torn down mid-request is not an unreachable server.
            throw CancellationError()
        } catch {
            throw DevysHTTPError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw DevysHTTPError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            return (data, http)
        case 401:
            throw DevysHTTPError.unauthorized
        default:
            let message = String(bytes: data.prefix(500), encoding: .utf8) ?? ""
            throw DevysHTTPError.rejected(status: http.statusCode, message: message)
        }
    }
}
