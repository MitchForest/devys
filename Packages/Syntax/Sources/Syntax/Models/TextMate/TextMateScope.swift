// TextMateScope.swift
// DevysSyntax
//
// Utilities for working with TextMate scope names.

import Foundation

enum TextMateScope {
    static func split(_ raw: String) -> [String] {
        raw.split { $0.isWhitespace }
            .map(String.init)
    }
}
