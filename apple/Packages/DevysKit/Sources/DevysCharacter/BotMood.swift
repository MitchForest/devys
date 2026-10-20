public import Foundation

/// Presentation-only state of a Bot's screen being. Projected from
/// conversation and work state by features; never persisted.
public enum BotMood: CaseIterable, Equatable, Sendable {
    case idle
    case listening
    case thinking
    case working
    case waiting
    case celebrate
    case oops
    case asleep
    case off

    /// Announced after the Bot's name when the avatar carries status.
    public var accessibilityDescription: String {
        switch self {
        case .idle: "available"
        case .listening: "listening"
        case .thinking: "thinking"
        case .working: "working"
        case .waiting: "waiting for you"
        case .celebrate: "finished a task"
        case .oops: "hit a snag"
        case .asleep: "asleep"
        case .off: "paused"
        }
    }
}

/// How much motion a rendered size can carry
/// (docs/product.md, The Face).
public enum MotionBudget: Equatable, Sendable {
    /// Static pose plus blink; sidebar-adjacent 24–27 pt sizes.
    case minimal
    /// Mood poses, gaze, and glyphs, but no locomotion; 28–63 pt.
    case poses
    /// Locomotion, props, and poke reactions; hero sizes.
    case full

    public init(size: Double) {
        if size < 28 {
            self = .minimal
        } else if size < 64 {
            self = .poses
        } else {
            self = .full
        }
    }
}
