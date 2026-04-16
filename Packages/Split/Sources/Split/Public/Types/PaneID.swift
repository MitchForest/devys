import Foundation

/// Opaque identifier for panes
public struct PaneID: Hashable, Codable, Sendable {
    internal let id: UUID

    public init() {
        self.id = UUID()
    }

    public init(uuid: UUID) {
        self.id = uuid
    }

    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.id = uuid
    }

    internal init(id: UUID) {
        self.id = id
    }

    public var uuid: UUID {
        id
    }

    public var uuidString: String {
        id.uuidString
    }
}
