import Foundation

/// Placement of a new pane relative to the target pane.
public enum SplitInsertionPosition: String, Codable, Equatable, Sendable {
    case before
    case after
}
