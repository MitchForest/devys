import DevysClient
import Foundation

/// The server's golden responses (DevysClientTests/Fixtures/wire, `bun run wire:write`).
nonisolated enum Golden {
    static func decode<Value: Decodable>(_ type: Value.Type, _ name: String) -> Value {
        let file = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../DevysClientTests/Fixtures/wire/\(name).json").standardized
        do {
            return try Wire.decoder().decode(type, from: Data(contentsOf: file))
        } catch {
            preconditionFailure("The golden \(name).json is unreadable: \(error)")
        }
    }
}

extension ModelCatalog {
    /// The deployment's real models and default, so tests never invent a catalog.
    nonisolated static let golden = Golden.decode(ModelCatalog.self, "models")
}
