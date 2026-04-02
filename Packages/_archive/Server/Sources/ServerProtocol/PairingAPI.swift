import Foundation

public enum PairingStatus: String, Codable, Sendable, CaseIterable {
    case active
    case revoked
}

public struct PairingChallengeRequest: Codable, Sendable, Equatable {
    public let deviceName: String?

    public init(deviceName: String? = nil) {
        self.deviceName = deviceName
    }
}

public struct PairingChallengeResponse: Codable, Sendable, Equatable {
    public let challengeID: String
    public let setupCode: String
    public let expiresAt: Date
    public let serverName: String
    public let serverFingerprint: String
    public let canonicalHostname: String?
    public let fallbackAddress: String?

    enum CodingKeys: String, CodingKey {
        case challengeID = "challengeId"
        case setupCode
        case expiresAt
        case serverName
        case serverFingerprint
        case canonicalHostname
        case fallbackAddress
    }

    public init(
        challengeID: String,
        setupCode: String,
        expiresAt: Date,
        serverName: String,
        serverFingerprint: String,
        canonicalHostname: String? = nil,
        fallbackAddress: String? = nil
    ) {
        self.challengeID = challengeID
        self.setupCode = setupCode
        self.expiresAt = expiresAt
        self.serverName = serverName
        self.serverFingerprint = serverFingerprint
        self.canonicalHostname = canonicalHostname
        self.fallbackAddress = fallbackAddress
    }
}

public struct PairingExchangeRequest: Codable, Sendable, Equatable {
    public let challengeID: String
    public let setupCode: String
    public let deviceName: String

    enum CodingKeys: String, CodingKey {
        case challengeID = "challengeId"
        case setupCode
        case deviceName
    }

    public init(challengeID: String, setupCode: String, deviceName: String) {
        self.challengeID = challengeID
        self.setupCode = setupCode
        self.deviceName = deviceName
    }
}

public struct PairingRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let deviceName: String
    public let createdAt: Date
    public let updatedAt: Date
    public let status: PairingStatus

    public init(
        id: String,
        deviceName: String,
        createdAt: Date,
        updatedAt: Date,
        status: PairingStatus
    ) {
        self.id = id
        self.deviceName = deviceName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
    }
}

public struct PairingExchangeResponse: Codable, Sendable, Equatable {
    public let pairing: PairingRecord
    public let authToken: String

    public init(pairing: PairingRecord, authToken: String) {
        self.pairing = pairing
        self.authToken = authToken
    }
}

public struct ListPairingsResponse: Codable, Sendable, Equatable {
    public let pairings: [PairingRecord]

    public init(pairings: [PairingRecord]) {
        self.pairings = pairings
    }
}

public struct RotatePairingResponse: Codable, Sendable, Equatable {
    public let pairing: PairingRecord
    public let authToken: String
    public let rotatedAt: Date

    public init(pairing: PairingRecord, authToken: String, rotatedAt: Date) {
        self.pairing = pairing
        self.authToken = authToken
        self.rotatedAt = rotatedAt
    }
}

public struct RevokePairingResponse: Codable, Sendable, Equatable {
    public let pairing: PairingRecord

    public init(pairing: PairingRecord) {
        self.pairing = pairing
    }
}
