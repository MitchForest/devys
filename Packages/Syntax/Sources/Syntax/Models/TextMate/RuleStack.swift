// RuleStack.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Manages the nested rule state during TextMate tokenization.
// The stack tracks which patterns are active and their scopes.

import Foundation

// MARK: - Rule Stack

/// Manages nested rule state during tokenization
public struct RuleStack: Sendable, Equatable, Hashable {
    /// Stack of active rule frames
    private var frames: [RuleFrame]

    /// The root scope name
    public let rootScopeName: String

    // MARK: - Initialization

    /// Create initial state for a grammar
    public static func initial(scopeName: String) -> RuleStack {
        RuleStack(
            frames: [
                RuleFrame(
                    scopeNames: [scopeName],
                    grammarScopeName: scopeName,
                    endPattern: nil,
                    whilePattern: nil,
                    whileCaptures: nil,
                    applyEndPatternLast: false,
                    endCaptures: nil,
                    contentName: nil,
                    nestedPatterns: nil,
                    anchorPosition: 0
                )
            ],
            rootScopeName: scopeName
        )
    }

    /// Create a custom rule stack with provided scopes.
    public static func fromScopes(
        _ scopes: [String],
        grammarScopeName: String,
        nestedPatterns: [TMPattern]? = nil,
        anchorPosition: Int = 0
    ) -> RuleStack {
        RuleStack(
            frames: [
                RuleFrame(
                    scopeNames: scopes,
                    grammarScopeName: grammarScopeName,
                    endPattern: nil,
                    whilePattern: nil,
                    whileCaptures: nil,
                    applyEndPatternLast: false,
                    endCaptures: nil,
                    contentName: nil,
                    nestedPatterns: nestedPatterns,
                    anchorPosition: anchorPosition
                )
            ],
            rootScopeName: grammarScopeName
        )
    }

    private init(frames: [RuleFrame], rootScopeName: String) {
        self.frames = frames
        self.rootScopeName = rootScopeName
    }

    // MARK: - Accessors

    /// Current accumulated scopes (from root to deepest)
    /// Includes content name if we're inside a begin/end block
    public var scopes: [String] {
        var result: [String] = []
        for frame in frames {
            for scopeName in frame.scopeNames {
                result.append(contentsOf: TextMateScope.split(scopeName))
            }
            // Add content name if present (for tokens inside the block)
            if let contentName = frame.contentName {
                result.append(contentsOf: TextMateScope.split(contentName))
            }
        }
        return result
    }

    /// Scopes without the content name (for begin/end tokens themselves)
    public var scopesWithoutContent: [String] {
        var result: [String] = []
        for (index, frame) in frames.enumerated() {
            for scopeName in frame.scopeNames {
                result.append(contentsOf: TextMateScope.split(scopeName))
            }
            if index < frames.count - 1, let contentName = frame.contentName {
                result.append(contentsOf: TextMateScope.split(contentName))
            }
        }
        return result
    }

    /// Current scope path as a single string
    public var scopePath: String {
        scopes.joined(separator: " ")
    }

    /// The end pattern of the current rule (if in a begin/end block)
    public var endPattern: String? {
        frames.last?.endPattern
    }

    /// While pattern of current rule (if any)
    public var whilePattern: String? {
        frames.last?.whilePattern
    }

    /// While captures of current rule (if any)
    public var whileCaptures: [String: TMCapture]? {
        frames.last?.whileCaptures
    }

    /// End captures of current rule (if any)
    public var endCaptures: [String: TMCapture]? {
        frames.last?.endCaptures
    }

    /// Whether end pattern should be applied after nested patterns
    public var applyEndPatternLast: Bool {
        frames.last?.applyEndPatternLast ?? false
    }

    /// Content name of current rule (if any)
    public var contentName: String? {
        frames.last?.contentName
    }

    /// Grammar scope name of current rule
    public var grammarScopeName: String {
        frames.last?.grammarScopeName ?? rootScopeName
    }

    /// Nested patterns from the current rule
    public var nestedPatterns: [TMPattern]? {
        frames.last?.nestedPatterns
    }

    /// Anchor position for \G matches (UTF-16 offset)
    public var anchorPosition: Int {
        frames.last?.anchorPosition ?? 0
    }

    /// Depth of the stack
    public var depth: Int {
        frames.count
    }

    /// Whether we're at the root level
    public var isAtRoot: Bool {
        frames.count == 1
    }

    /// Find the deepest (top-most) while pattern in the stack.
    public func deepestWhilePattern() -> (pattern: String, index: Int, captures: [String: TMCapture]?, anchor: Int)? {
        for (index, frame) in frames.enumerated().reversed() {
            if let pattern = frame.whilePattern {
                return (pattern: pattern, index: index, captures: frame.whileCaptures, anchor: frame.anchorPosition)
            }
        }
        return nil
    }

    /// All while patterns in the stack, ordered from deepest to shallowest.
    public func whileFrames() -> [(pattern: String, index: Int, captures: [String: TMCapture]?, anchor: Int)] {
        var result: [(pattern: String, index: Int, captures: [String: TMCapture]?, anchor: Int)] = []
        for (index, frame) in frames.enumerated().reversed() {
            if let pattern = frame.whilePattern {
                result.append(
                    (
                        pattern: pattern,
                        index: index,
                        captures: frame.whileCaptures,
                        anchor: frame.anchorPosition
                    )
                )
            }
        }
        return result
    }

    /// Pop to a specific depth (inclusive). Depth 0 keeps only root frame.
    public func popTo(depth: Int) -> RuleStack {
        let clampedDepth = max(0, depth)
        let newFrames = Array(frames.prefix(clampedDepth + 1))
        return RuleStack(frames: newFrames, rootScopeName: rootScopeName)
    }

    // MARK: - Stack Operations

    /// Push a new rule onto the stack
    public func push(
        scopeNames: [String],
        grammarScopeName: String,
        endPattern: String?,
        whilePattern: String? = nil,
        whileCaptures: [String: TMCapture]? = nil,
        applyEndPatternLast: Bool = false,
        endCaptures: [String: TMCapture]? = nil,
        contentName: String?,
        nestedPatterns: [TMPattern]? = nil,
        anchorPosition: Int
    ) -> RuleStack {
        var newFrames = frames
        newFrames.append(RuleFrame(
            scopeNames: scopeNames,
            grammarScopeName: grammarScopeName,
            endPattern: endPattern,
            whilePattern: whilePattern,
            whileCaptures: whileCaptures,
            applyEndPatternLast: applyEndPatternLast,
            endCaptures: endCaptures,
            contentName: contentName,
            nestedPatterns: nestedPatterns,
            anchorPosition: anchorPosition
        ))
        return RuleStack(frames: newFrames, rootScopeName: rootScopeName)
    }

    /// Pop the current rule from the stack
    public func pop() -> RuleStack {
        guard frames.count > 1 else {
            // Don't pop the root frame
            return self
        }

        var newFrames = frames
        newFrames.removeLast()
        return RuleStack(frames: newFrames, rootScopeName: rootScopeName)
    }

    /// Add content scope to current frame
    public func withContentScope(_ scopeName: String) -> RuleStack {
        guard !frames.isEmpty else { return self }

        var newFrames = frames
        var lastFrame = newFrames.removeLast()
        lastFrame.scopeNames.append(contentsOf: TextMateScope.split(scopeName))
        newFrames.append(lastFrame)
        return RuleStack(frames: newFrames, rootScopeName: rootScopeName)
    }

    public func resetAnchors() -> RuleStack {
        var newFrames = frames
        for index in newFrames.indices {
            newFrames[index].anchorPosition = 0
        }
        return RuleStack(frames: newFrames, rootScopeName: rootScopeName)
    }

    // MARK: - Equatable/Hashable

    public static func == (lhs: RuleStack, rhs: RuleStack) -> Bool {
        // Compare frames by their hashable parts (exclude patterns for equality)
        guard lhs.frames.count == rhs.frames.count else { return false }
        guard lhs.rootScopeName == rhs.rootScopeName else { return false }

        for (l, r) in zip(lhs.frames, rhs.frames) {
            if l.scopeNames != r.scopeNames { return false }
            if l.grammarScopeName != r.grammarScopeName { return false }
            if l.endPattern != r.endPattern { return false }
            if l.whilePattern != r.whilePattern { return false }
            if l.applyEndPatternLast != r.applyEndPatternLast { return false }
            if l.endCaptures?.count != r.endCaptures?.count { return false }
            if l.contentName != r.contentName { return false }
            if l.anchorPosition != r.anchorPosition { return false }
        }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        for frame in frames {
            hasher.combine(frame.scopeNames)
            hasher.combine(frame.grammarScopeName)
            hasher.combine(frame.endPattern)
            hasher.combine(frame.whilePattern)
            hasher.combine(frame.applyEndPatternLast)
            hasher.combine(frame.endCaptures?.count ?? 0)
            hasher.combine(frame.contentName)
            hasher.combine(frame.anchorPosition)
        }
        hasher.combine(rootScopeName)
    }
}

// MARK: - Rule Frame

/// A single frame in the rule stack
struct RuleFrame: Sendable {
    /// Scope names contributed by this frame
    var scopeNames: [String]

    /// Grammar scope this frame belongs to
    var grammarScopeName: String

    /// The end pattern to watch for (if begin/end rule)
    var endPattern: String?

    /// The while pattern to validate continuation (if begin/while rule)
    var whilePattern: String?

    /// While-capture scopes (optional)
    var whileCaptures: [String: TMCapture]?

    /// Whether end pattern should be applied after nested patterns
    var applyEndPatternLast: Bool

    /// End-capture scopes (optional)
    var endCaptures: [String: TMCapture]?

    /// Content name scope (if any)
    var contentName: String?

    /// Nested patterns to apply while in this rule
    var nestedPatterns: [TMPattern]?

    /// Anchor position for \G matches (UTF-16 offset)
    var anchorPosition: Int
}

// MARK: - Debug

extension RuleStack: CustomDebugStringConvertible {
    public var debugDescription: String {
        "RuleStack(\(scopes.joined(separator: " > ")))"
    }
}
