import ACPClientKit
import Foundation
import Testing

@Suite("ACP Protocol Compatibility Tests")
struct ACPProtocolCompatibilityTests {
    @Test("Client capabilities encode as a direct object")
    func clientCapabilitiesEncodeAsDirectObject() throws {
        let capabilities = ACPClientCapabilities.standard(
            fileSystem: ACPFileSystemCapabilities(
                readTextFile: true,
                writeTextFile: true
            ),
            terminal: true
        )

        let data = try JSONEncoder().encode(capabilities)
        let jsonObject = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(jsonObject["values"] == nil)
        let fs = try #require(jsonObject["fs"] as? [String: Bool])
        #expect(fs["readTextFile"] == true)
        #expect(fs["writeTextFile"] == true)
        #expect(jsonObject["terminal"] as? Bool == true)
    }

    @Test("Server capabilities decode from direct initialize payloads")
    func serverCapabilitiesDecodeFromDirectObject() throws {
        let data = Data(
            """
            {
              "protocolVersion": 1,
              "agentCapabilities": {
                "loadSession": true,
                "promptCapabilities": {
                  "image": true,
                  "embeddedContext": true
                },
                "sessionCapabilities": {
                  "list": {},
                  "close": {}
                }
              },
              "agentInfo": {
                "name": "codex-acp",
                "version": "0.11.1"
              }
            }
            """.utf8
        )

        let result = try JSONDecoder().decode(ACPInitializeResult.self, from: data)

        #expect(result.protocolVersion == 1)
        #expect(result.capabilities.loadSession)
        #expect(result.capabilities.promptCapabilities.image)
        #expect(result.capabilities.promptCapabilities.embeddedContext)
        #expect(result.capabilities.supports("sessionCapabilities.list"))
        #expect(result.serverInfo?.name == "codex-acp")
    }

    @Test("Legacy wrapped capability objects still decode")
    func wrappedCapabilitiesStillDecode() throws {
        let data = Data(
            """
            {
              "agentCapabilities": {
                "values": {
                  "loadSession": true
                }
              }
            }
            """.utf8
        )

        let result = try JSONDecoder().decode(ACPInitializeResult.self, from: data)

        #expect(result.capabilities.loadSession)
    }

    @Test("Session identifiers decode from scalar ACP payloads")
    func sessionIdentifiersDecodeFromScalars() throws {
        let data = Data(
            """
            {
              "sessionId": "019d6ad1-ec7b-7462-b417-6a619fd29438"
            }
            """.utf8
        )

        struct Payload: Decodable {
            var sessionId: ACPSessionID
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)

        #expect(payload.sessionId.rawValue == "019d6ad1-ec7b-7462-b417-6a619fd29438")
    }
}
