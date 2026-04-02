import Foundation
import Network
import ServerProtocol

extension HTTPServer {
    func handleListCommandProfiles(on connection: NWConnection) {
        let profiles = commandProfiles.values.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
        sendJSON(statusCode: 200, payload: ListCommandProfilesResponse(profiles: profiles), on: connection)
    }

    func handleSaveCommandProfile(request: HTTPRequest, on connection: NWConnection) {
        let saveRequest: SaveCommandProfileRequest
        do {
            saveRequest = try ServerJSONCoding.makeDecoder().decode(SaveCommandProfileRequest.self, from: request.body)
        } catch {
            sendError(
                statusCode: 400,
                code: "invalid_request",
                message: "Unable to decode save profile payload",
                on: connection
            )
            return
        }

        let normalized = saveRequest.profile.normalizedForStorage
        let validation = validateCommandProfile(normalized)
        guard validation.isValid else {
            sendError(
                statusCode: 422,
                code: "invalid_profile",
                message: validation.errors.joined(separator: " "),
                details: ["errors": .array(validation.errors.map(JSONValue.string))],
                on: connection
            )
            return
        }

        commandProfiles[normalized.id] = normalized
        persistCommandProfiles()
        sendJSON(statusCode: 200, payload: SaveCommandProfileResponse(profile: normalized), on: connection)
    }

    func handleValidateCommandProfile(request: HTTPRequest, on connection: NWConnection) {
        let validateRequest: ValidateCommandProfileRequest
        do {
            validateRequest = try ServerJSONCoding.makeDecoder().decode(
                ValidateCommandProfileRequest.self,
                from: request.body
            )
        } catch {
            sendError(
                statusCode: 400,
                code: "invalid_request",
                message: "Unable to decode validate profile payload",
                on: connection
            )
            return
        }

        let validation = validateCommandProfile(validateRequest.profile.normalizedForStorage)
        sendJSON(statusCode: 200, payload: validation, on: connection)
    }

    func handleDeleteCommandProfile(request: HTTPRequest, on connection: NWConnection) {
        let deleteRequest: DeleteCommandProfileRequest
        do {
            deleteRequest = try ServerJSONCoding.makeDecoder().decode(
                DeleteCommandProfileRequest.self,
                from: request.body
            )
        } catch {
            sendError(
                statusCode: 400,
                code: "invalid_request",
                message: "Unable to decode delete profile payload",
                on: connection
            )
            return
        }

        let profileID = deleteRequest.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !profileID.isEmpty else {
            sendError(
                statusCode: 422,
                code: "invalid_profile_id",
                message: "Profile id is required",
                on: connection
            )
            return
        }

        guard let existing = commandProfiles[profileID] else {
            sendError(statusCode: 404, code: "profile_not_found", message: "Profile not found", on: connection)
            return
        }

        if existing.isDefault {
            sendError(
                statusCode: 409,
                code: "default_profile_protected",
                message: "Default command profiles cannot be deleted",
                on: connection
            )
            return
        }

        commandProfiles.removeValue(forKey: profileID)
        persistCommandProfiles()
        sendJSON(statusCode: 200, payload: DeleteCommandProfileResponse(deletedID: profileID), on: connection)
    }

    func validateCommandProfile(_ profile: CommandProfile) -> ValidateCommandProfileResponse {
        var errors: [String] = []
        var warnings: [String] = []

        if profile.id.isEmpty {
            errors.append("Profile id is required")
        }

        if profile.id.range(of: "^[a-z0-9_-]{1,32}$", options: .regularExpression) == nil {
            errors.append("Profile id must match ^[a-z0-9_-]{1,32}$")
        }

        if profile.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Profile label is required")
        }

        if let command = profile.command {
            if command.isEmpty {
                errors.append("Command must not be empty when provided")
            }
            if command.contains("\n") {
                errors.append("Command must be a single line")
            }
        } else if profile.arguments.isEmpty == false || profile.environment.isEmpty == false {
            warnings.append("Arguments/environment are ignored when command is empty")
        }

        for key in profile.environment.keys where key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Environment keys must not be empty")
            break
        }

        let isValid = errors.isEmpty
        return ValidateCommandProfileResponse(isValid: isValid, errors: errors, warnings: warnings)
    }
}
