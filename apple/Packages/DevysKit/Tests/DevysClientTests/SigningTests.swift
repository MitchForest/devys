import CryptoKit
import DevysClient
import Foundation
import Testing

/// The spend approval a device signs is the server's canonical payload, byte for byte
/// (tests/signing.test.ts writes the golden file from src/authority/signing.ts).
@Suite("Signed spend approvals")
struct SigningTests {
    private struct Golden: Decodable {
        let businessID: String
        let decision: Decision
        let payload: String
        let publicKey: String
        let signature: String

        enum CodingKeys: String, CodingKey {
            case decision, payload, signature
            case businessID = "business_id"
            case publicKey = "public_key"
        }
    }

    private static func golden() throws -> Golden {
        let url = try #require(Bundle.module.url(forResource: "spend-approval", withExtension: "json", subdirectory: "Fixtures/signing"))
        return try Wire.decoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    @Test("The payload built here from the decision is the server's, escapes and all")
    func canonical() throws {
        let golden = try Self.golden()
        let approval = try #require(SpendApproval(golden.decision, businessID: golden.businessID))
        #expect(approval.canonical == golden.payload)
        #expect(approval.amount.text == "$12.99" && approval.counterparty == "Namecheap")
    }

    @Test("A DER signature over the payload's UTF-8 bytes verifies with the X9.63 public key, as the server verifies it")
    func verifies() throws {
        let golden = try Self.golden()
        let key = try P256.Signing.PublicKey(x963Representation: try #require(Data(base64Encoded: golden.publicKey)))
        let signature = try P256.Signing.ECDSASignature(derRepresentation: try #require(Data(base64Encoded: golden.signature)))
        #expect(key.isValidSignature(signature, for: Data(golden.payload.utf8)))
        #expect(!key.isValidSignature(signature, for: Data(golden.payload.replacingOccurrences(of: "1299", with: "1300").utf8)))
    }

    @Test("Only an approve with an amount and a work item is a spend")
    func onlySpends() {
        let approve = Decision(
            id: "d1", kind: .approve, employeeID: "e1", capability: "askOwner",
            input: .object(["kind": .string("approve"), "action": .string("Merge"), "counterparty": .string("GitHub")]),
            workItemID: "w1"
        )
        #expect(!approve.isSpend && SpendApproval(approve, businessID: "b1") == nil)
        #expect(approve.request == .approve(action: "Merge", counterparty: "GitHub", amount: nil, renewal: nil))
        let ask = Decision(id: "d2", employeeID: "e1", capability: "driveCreate", input: .object(["amount": .object(["cents": .number(5)])]))
        #expect(ask.request == nil && !ask.isSpend)
    }

    @Test("A device's software key signs payloads the same way (the simulator's stand-in)")
    func softwareKey() async throws {
        let signer = DeviceSigner.software()
        let key = try P256.Signing.PublicKey(x963Representation: try signer.publicKey())
        let golden = try Self.golden()
        let der = try await signer.sign(Data(golden.payload.utf8), "approve")
        #expect(key.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: der), for: Data(golden.payload.utf8)))
        #expect(try signer.publicKey() == key.x963Representation)
    }
}
