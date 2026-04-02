// GitCommit.swift
// Model for a git commit.

import Foundation

/// A git commit.
struct GitCommit: Identifiable, Equatable, Hashable, Sendable {
    var id: String { hash }
    
    let hash: String
    let shortHash: String
    let authorName: String
    let date: Date
    let message: String
    
    init(
        hash: String,
        shortHash: String,
        authorName: String,
        date: Date,
        message: String
    ) {
        self.hash = hash
        self.shortHash = shortHash
        self.authorName = authorName
        self.date = date
        self.message = message
    }
    
    /// First line of the commit message.
    var subject: String {
        message.components(separatedBy: .newlines).first ?? message
    }
    
    /// Relative date string (e.g., "2 hours ago").
    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
