// CodexJSON.swift
// Sendable wrapper for JSON-like dictionaries returned by Codex.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Wrapper around JSON dictionaries returned by Codex.
///
/// ## Thread Safety
///
/// This type is `@unchecked Sendable` because `[String: Any]` cannot be verified
/// by the compiler, but is safe in practice because:
///
/// 1. **Immutable**: The `value` property is `let` and never mutated after init
/// 2. **JSON-safe types only**: Values come from `JSONSerialization.jsonObject()` which
///    produces only JSON-compatible types: `String`, `NSNumber`, `Bool`, `NSNull`,
///    `[Any]`, `[String: Any]` - all of which are immutable value semantics
/// 3. **No shared mutable state**: Each `CodexJSON` instance owns its data
///
/// A future improvement would be to use a `JSONValue` enum for type-safe Sendable,
/// but the current approach is safe for Codex JSON-RPC responses.
public struct CodexJSON: @unchecked Sendable {
    public let value: [String: Any]

    public init(_ value: [String: Any]) {
        self.value = value
    }

}

/// Wrapper around JSON arrays returned by Codex.
///
/// ## Thread Safety
///
/// See `CodexJSON` for thread-safety rationale. Same guarantees apply.
public struct CodexJSONArray: @unchecked Sendable {
    public let value: [[String: Any]]

    public init(_ value: [[String: Any]]) {
        self.value = value
    }
}
