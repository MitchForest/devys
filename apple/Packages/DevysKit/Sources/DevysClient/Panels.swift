public import Dependencies
import Foundation

/// Whether each kind of conversation shows its right panel, as the owner last left it.
public struct PanelsClient: Sendable {
    public var load: @Sendable () -> [String: Bool]
    public var save: @Sendable ([String: Bool]) -> Void

    public init(load: @escaping @Sendable () -> [String: Bool], save: @escaping @Sendable ([String: Bool]) -> Void) {
        self.load = load
        self.save = save
    }

    public static let userDefaults = Self(
        load: { UserDefaults.standard.dictionary(forKey: "panels") as? [String: Bool] ?? [:] },
        save: { UserDefaults.standard.set($0, forKey: "panels") }
    )

    /// Nothing remembered: every kind starts at its default.
    public static let defaults = Self(load: { [:] }, save: { _ in })
}

nonisolated enum PanelsClientKey: DependencyKey {
    static let liveValue = PanelsClient.userDefaults
    static let testValue = PanelsClient.defaults
    static let previewValue = PanelsClient.defaults
}

extension DependencyValues {
    public var panelsClient: PanelsClient {
        get { self[PanelsClientKey.self] }
        set { self[PanelsClientKey.self] = newValue }
    }
}
