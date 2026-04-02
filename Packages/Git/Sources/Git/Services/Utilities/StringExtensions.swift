// StringExtensions.swift
// UTF-16 indexing helpers for diff rendering.

import Foundation

extension String {
    func utf16Index(at offset: Int) -> String.Index {
        let clamped = min(offset, utf16.count)
        let utf16Index = utf16.index(utf16.startIndex, offsetBy: clamped)
        return String.Index(utf16Index, within: self) ?? endIndex
    }
}
