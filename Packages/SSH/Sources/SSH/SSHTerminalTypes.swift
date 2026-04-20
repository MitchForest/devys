import Foundation

public enum SSHAuthenticationMethod: Sendable, Equatable, Codable {
    case password(String)
    case privateKey(privateKeyPEM: String, passphrase: String?)
}

public struct SSHConnectionConfiguration: Sendable, Equatable, Codable {
    public var host: String
    public var port: Int
    public var username: String
    public var authentication: SSHAuthenticationMethod

    public init(
        host: String,
        port: Int = 22,
        username: String,
        authentication: SSHAuthenticationMethod
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.authentication = authentication
    }
}

public struct SSHHostKeyValidationContext: Sendable, Equatable, Codable {
    public var host: String
    public var port: Int
    public var algorithm: String
    public var openSSHPublicKey: String
    public var fingerprintSHA256: String

    public init(
        host: String,
        port: Int,
        algorithm: String,
        openSSHPublicKey: String,
        fingerprintSHA256: String
    ) {
        self.host = host
        self.port = port
        self.algorithm = algorithm
        self.openSSHPublicKey = openSSHPublicKey
        self.fingerprintSHA256 = fingerprintSHA256
    }
}

public typealias SSHHostKeyValidator = @MainActor @Sendable (
    SSHHostKeyValidationContext
) async -> SSHHostKeyValidationDecision

public enum SSHHostKeyValidationDecision: Sendable, Equatable {
    case trust
    case reject
}

public enum SSHTerminalError: Error, Sendable, LocalizedError {
    case invalidHost
    case invalidPort
    case notConnected
    case unsupportedPrivateKeyFormat
    case encryptedPrivateKeyUnsupported
    case hostKeyRejected
    case invalidServerHostKey
    case invalidTerminalDimensions
    case failedToOpenShellChannel

    public var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Host is required."
        case .invalidPort:
            return "Port must be between 1 and 65535."
        case .notConnected:
            return "SSH session is not connected."
        case .unsupportedPrivateKeyFormat:
            return "Private key format is unsupported. Use password auth, " +
                "unencrypted OpenSSH Ed25519, or unencrypted P-256/P-384/P-521 PEM keys."
        case .encryptedPrivateKeyUnsupported:
            return "Encrypted private keys are not supported yet. Use password auth or an unencrypted key."
        case .hostKeyRejected:
            return "Host key was rejected."
        case .invalidServerHostKey:
            return "Server host key is invalid."
        case .invalidTerminalDimensions:
            return "Terminal dimensions are invalid."
        case .failedToOpenShellChannel:
            return "Failed to open SSH shell channel."
        }
    }
}
