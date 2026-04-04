// StringExtensions.swift
// Syntax string helpers
//
// String utilities for UTF-16 indexing and other operations.

import Foundation

// MARK: - UTF-16 String Extensions

extension String {
    /// Get the UTF-16 count of the string
    var utf16Count: Int {
        utf16.count
    }
    
    /// Get a String.Index from a UTF-16 offset
    func utf16Index(at offset: Int) -> String.Index {
        let utf16Index = utf16.index(utf16.startIndex, offsetBy: min(offset, utf16.count))
        return utf16Index
    }
    
    /// Get the next character boundary after a UTF-16 offset
    /// This handles multi-byte characters properly
    func nextCharacterBoundary(afterUtf16Offset offset: Int) -> Int {
        guard offset < utf16Count else { return utf16Count }
        
        let startIndex = utf16Index(at: offset)
        guard startIndex < endIndex else { return utf16Count }
        
        let nextIndex = index(after: startIndex)
        return nextIndex.utf16Offset(in: self)
    }
}

// MARK: - Range Utilities

extension String.Index {
    /// Get the UTF-16 offset of this index in a string
    func utf16Offset(in string: String) -> Int {
        string.utf16.distance(from: string.utf16.startIndex, to: self)
    }
}
