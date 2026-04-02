import ChatCore

extension HarnessType: Identifiable {}

public extension HarnessType {
    /// Stable identifier for list/ForEach usages.
    var id: String { rawValue }

    /// All known harness types. Use this instead of `allCases` since `HarnessType` is
    /// a `RawRepresentable` struct (extensible), not a closed enum.
    public static let allKnown: [HarnessType] = [.codex, .claudeCode]

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        default: return rawValue
        }
    }

    /// Short display name for compact UI.
    public var shortName: String {
        switch self {
        case .codex: return "CX"
        case .claudeCode: return "CC"
        default: return rawValue.prefix(2).uppercased()
        }
    }

    /// SF Symbol icon name.
    public var iconName: String {
        switch self {
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .claudeCode: return "brain"
        default: return "bubble.left.fill"
        }
    }
}
