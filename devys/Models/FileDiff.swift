//
//  FileDiff.swift
//  devys
//
//  A file diff from the CLI stream.
//  NOT persisted - parsed from CLI output.
//

import Foundation

/// A file diff produced by the agent.
/// Parsed from CLI JSON-RPC events.
struct FileDiff: Identifiable, Hashable {
    let id: String
    let path: String
    let content: String
    let linesAdded: Int
    let linesRemoved: Int
    
    init(
        id: String = UUID().uuidString,
        path: String,
        content: String = "",
        linesAdded: Int = 0,
        linesRemoved: Int = 0
    ) {
        self.id = id
        self.path = path
        self.content = content
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }
    
    /// File extension
    var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }
    
    /// Icon based on file type
    var icon: String {
        switch fileExtension {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces"
        case "md", "markdown": return "doc.text"
        default: return "doc.text"
        }
    }
    
    /// Summary string (e.g., "+5 -2")
    var summary: String {
        var parts: [String] = []
        if linesAdded > 0 { parts.append("+\(linesAdded)") }
        if linesRemoved > 0 { parts.append("-\(linesRemoved)") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: " ")
    }
}
