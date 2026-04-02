import CryptoKit
import Foundation
@preconcurrency import NIOSSH

enum SSHPrivateKeyParseResult {
    case success(NIOSSHPrivateKey)
    case encryptedUnsupported
    case unsupported
}

enum SSHPrivateKeyParser {
    static func parse(privateKeyPEM: String) -> SSHPrivateKeyParseResult {
        if let parsed = parseCurvePEMKey(privateKeyPEM: privateKeyPEM) {
            return .success(parsed)
        }

        if let openSSHParsed = parseOpenSSHEd25519Key(privateKeyPEM: privateKeyPEM) {
            return openSSHParsed
        }

        return .unsupported
    }
}

private extension SSHPrivateKeyParser {
    enum OpenSSHHeader {
        case unsupported
        case encryptedUnsupported
        case privateBlock(Data)
    }

    static func parseCurvePEMKey(privateKeyPEM: String) -> NIOSSHPrivateKey? {
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM) {
            return NIOSSHPrivateKey(p256Key: key)
        }
        if let key = try? P384.Signing.PrivateKey(pemRepresentation: privateKeyPEM) {
            return NIOSSHPrivateKey(p384Key: key)
        }
        if let key = try? P521.Signing.PrivateKey(pemRepresentation: privateKeyPEM) {
            return NIOSSHPrivateKey(p521Key: key)
        }
        return nil
    }

    static func parseOpenSSHEd25519Key(privateKeyPEM: String) -> SSHPrivateKeyParseResult? {
        guard let blob = readOpenSSHBlob(privateKeyPEM: privateKeyPEM) else { return nil }

        switch parseOpenSSHHeader(blob: blob) {
        case .unsupported:
            return .unsupported
        case .encryptedUnsupported:
            return .encryptedUnsupported
        case .privateBlock(let privateBlock):
            return parseOpenSSHPrivateBlock(privateBlock)
        }
    }

    static func readOpenSSHBlob(privateKeyPEM: String) -> Data? {
        let beginMarker = "-----BEGIN OPENSSH PRIVATE KEY-----"
        let endMarker = "-----END OPENSSH PRIVATE KEY-----"

        guard let beginRange = privateKeyPEM.range(of: beginMarker),
              let endRange = privateKeyPEM.range(of: endMarker),
              beginRange.upperBound <= endRange.lowerBound else {
            return nil
        }

        let base64Slice = privateKeyPEM[beginRange.upperBound..<endRange.lowerBound]
        let base64Body = String(base64Slice).components(separatedBy: .whitespacesAndNewlines).joined()
        guard let blob = Data(base64Encoded: base64Body), !blob.isEmpty else {
            return Data()
        }
        return blob
    }

    static func parseOpenSSHHeader(blob: Data) -> OpenSSHHeader {
        guard !blob.isEmpty else { return .unsupported }

        var headerReader = SSHBinaryReader(data: blob)
        guard headerReader.readPrefix(Data("openssh-key-v1\0".utf8)) else {
            return .unsupported
        }
        guard let cipherName = headerReader.readSSHStringUTF8(),
              let kdfName = headerReader.readSSHStringUTF8(),
              let kdfOptions = headerReader.readSSHStringData(),
              let keyCount = headerReader.readUInt32() else {
            return .unsupported
        }

        guard cipherName == "none", kdfName == "none", kdfOptions.isEmpty else {
            return .encryptedUnsupported
        }

        guard keyCount > 0 else { return .unsupported }
        for _ in 0..<keyCount {
            guard headerReader.readSSHStringData() != nil else {
                return .unsupported
            }
        }

        guard let privateBlock = headerReader.readSSHStringData() else {
            return .unsupported
        }
        return .privateBlock(privateBlock)
    }

    static func parseOpenSSHPrivateBlock(_ privateBlock: Data) -> SSHPrivateKeyParseResult {
        var keyReader = SSHBinaryReader(data: privateBlock)
        guard let checkA = keyReader.readUInt32(),
              let checkB = keyReader.readUInt32(),
              checkA == checkB else {
            return .unsupported
        }

        guard let keyType = keyReader.readSSHStringUTF8(),
              keyType == "ssh-ed25519",
              keyReader.readSSHStringData() != nil,
              let privateKeyBytes = keyReader.readSSHStringData(),
              privateKeyBytes.count >= 32,
              keyReader.readSSHStringData() != nil else {
            return .unsupported
        }

        let seed = Data(privateKeyBytes.prefix(32))
        guard let curveKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
            return .unsupported
        }
        return .success(NIOSSHPrivateKey(ed25519Key: curveKey))
    }
}

private struct SSHBinaryReader {
    let data: Data
    private(set) var index = 0

    var remainingBytes: Int {
        max(0, data.count - index)
    }

    mutating func readPrefix(_ expected: Data) -> Bool {
        guard let bytes = readData(count: expected.count) else { return false }
        return bytes == expected
    }

    mutating func readUInt32() -> UInt32? {
        guard let raw = readData(count: 4) else { return nil }
        var value: UInt32 = 0
        for byte in raw {
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    mutating func readSSHStringData() -> Data? {
        guard let length = readUInt32() else { return nil }
        let count = Int(length)
        guard count <= remainingBytes else { return nil }
        return readData(count: count)
    }

    mutating func readSSHStringUTF8() -> String? {
        guard let bytes = readSSHStringData() else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    mutating func readData(count: Int) -> Data? {
        guard count >= 0 else { return nil }
        guard count <= remainingBytes else { return nil }
        let start = data.index(data.startIndex, offsetBy: index)
        let end = data.index(start, offsetBy: count)
        index += count
        return data[start..<end]
    }
}
