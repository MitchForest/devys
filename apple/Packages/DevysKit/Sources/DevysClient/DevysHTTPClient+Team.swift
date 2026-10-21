public import Foundation

/// Devices, businesses and their teams, and connections.
extension DevysHTTPClient {
    public func devices(_ session: DeviceSession) async throws -> [Device] {
        struct Page: Decodable { let devices: [Device] }
        let page: Page = try await send(authorized(session, path: "api/devices"))
        return page.devices
    }

    /// Issues a ten-minute, single-use code that signs another device in as this person.
    public func issueDeviceCode(_ session: DeviceSession) async throws -> DeviceCode {
        let issued: IssuedCode = try await send(authorized(session, path: "api/devices/codes", method: "POST"))
        return DeviceCode(code: issued.code, expiresAt: issued.expiresAt, server: session.server)
    }

    /// Signs one of the person's devices out.
    public func revokeDevice(_ session: DeviceSession, id: String) async throws {
        _ = try await raw(authorized(session, path: "api/devices/\(id)/revoke", method: "POST"))
    }

    public func roles(_ session: DeviceSession) async throws -> [RoleTemplate] {
        struct Page: Decodable { let roles: [RoleTemplate] }
        let page: Page = try await send(authorized(session, path: "api/roles"))
        return page.roles
    }

    /// Renames a business or rewrites its brief; returns the business as saved.
    public func updateBusiness(_ session: DeviceSession, id: String, name: String?, brief: String?) async throws -> Business {
        struct Body: Encodable { let name: String?; let brief: String? }
        struct Saved: Decodable { let business: Business }
        let saved: Saved = try await send(json(session, path: "api/businesses/\(id)", method: "PUT", body: Body(name: name, brief: brief)))
        return saved.business
    }

    /// Hires an employee from a role template; it starts with that template's grants.
    public func hire(_ session: DeviceSession, businessID: String, _ hire: Hire) async throws -> Employee {
        try await send(json(session, path: "api/businesses/\(businessID)/employees", method: "POST", body: hire))
    }

    public func updateProfile(_ session: DeviceSession, _ scope: EmployeeScope, _ change: ProfileChange) async throws {
        _ = try await raw(json(session, path: "\(scope.path)/profile", method: "PUT", body: change))
    }

    /// Retires an employee; its open work moves to `reassignTo`. Returns who took it.
    public func retire(_ session: DeviceSession, _ scope: EmployeeScope, reassignTo: String) async throws -> String {
        struct Body: Encodable {
            let reassignTo: String
            enum CodingKeys: String, CodingKey { case reassignTo = "reassign_to" }
        }
        struct Retired: Decodable {
            let reassignedTo: String
            enum CodingKeys: String, CodingKey { case reassignedTo = "reassigned_to" }
        }
        let retired: Retired = try await send(json(session, path: "\(scope.path)/retire", method: "POST", body: Body(reassignTo: reassignTo)))
        return retired.reassignedTo
    }

    /// Everything the business has said and knows, as newline-delimited JSON (`GET …/export`).
    public func exportBusiness(_ session: DeviceSession, id: String) async throws -> Data {
        try await raw(authorized(session, path: "api/businesses/\(id)/export"))
    }

    public func googleConnection(_ session: DeviceSession, businessID: String) async throws -> GoogleConnection {
        try await send(authorized(session, path: "api/businesses/\(businessID)/connections/google"))
    }
}

/// `POST /api/devices/codes`.
struct IssuedCode: Decodable {
    let code: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case code
        case expiresAt = "expires_at"
    }
}
