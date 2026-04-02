import CryptoKit
import XCTest
@testable import ServerClient

final class SSHPrivateKeyParserTests: XCTestCase {
    func testParseAcceptsPEMP256Key() {
        let pem = P256.Signing.PrivateKey().pemRepresentation
        let result = SSHPrivateKeyParser.parse(privateKeyPEM: pem)

        guard case .success = result else {
            XCTFail("Expected PEM P-256 key to parse successfully.")
            return
        }
    }

    func testParseAcceptsUnencryptedOpenSSHEd25519Key() {
        let result = SSHPrivateKeyParser.parse(privateKeyPEM: Self.unencryptedOpenSSHEd25519)

        guard case .success = result else {
            XCTFail("Expected unencrypted OpenSSH Ed25519 key to parse successfully.")
            return
        }
    }

    func testParseRejectsEncryptedOpenSSHKey() {
        let result = SSHPrivateKeyParser.parse(privateKeyPEM: Self.encryptedOpenSSHEd25519)

        guard case .encryptedUnsupported = result else {
            XCTFail("Expected encrypted OpenSSH key to be marked unsupported.")
            return
        }
    }

    func testParseRejectsGarbageInput() {
        let result = SSHPrivateKeyParser.parse(privateKeyPEM: "not a key")

        guard case .unsupported = result else {
            XCTFail("Expected malformed input to be unsupported.")
            return
        }
    }
}

private extension SSHPrivateKeyParserTests {
    static let unencryptedOpenSSHEd25519 = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZWQyNTUxOQAAACCo/dKGSyNfqs0eDf4WRldq75rIraY8Rj8EyJK4vkncRAAAAJiggr23oIK9twAAAAtzc2gtZWQyNTUxOQAAACCo/dKGSyNfqs0eDf4WRldq75rIraY8Rj8EyJK4vkncRAAAAECOf5w3fCmt5eXNLxxKCE/0CWjGndqYzx32w2zUA7d/VKj90oZLI1+qzR4N/hZGV2rvmsitpjxGPwTIkri+SdxEAAAAEm1pdGNod2hpdGVATWFjLmxhbgECAw==
    -----END OPENSSH PRIVATE KEY-----
    """

    static let encryptedOpenSSHEd25519 = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABAlpE4Rp8TbOnsnP8TvORZFAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIJVIhf30lxvz54zTyEd2aHKmdkw0MHG/OpF5/W64kspFAAAAoAZLLjvEeH5rFazH5ZCzCZZf29IePxAnB3iPykBasoLLdkRhoPikHcU7PsrTL4ZqpT5GD7hGm1TKDjfdJYXYmNE+SLPe+1BPUjRnKnYwC1RZohFzq3cbf7CuI8KzcZaaAVdb6oGU8YD3OT8bAkACLjzosQMEx9DXbz5C+qjhoVLl+7+HsNiS782DkwZ6QhYhOTUA6546Xn4HxVnZrvsf8n0=
    -----END OPENSSH PRIVATE KEY-----
    """
}
