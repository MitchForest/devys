//
//  Thread.swift
//  devys
//
//  A thread is a conversation from the CLI.
//  NOT persisted - we get this from `thread/list` and `thread/resume`.
//

import Foundation

/// A conversation thread from the CLI.
/// We get these from `thread/list`, filtered by workspace path.
struct Thread: Identifiable, Hashable {
    /// Thread ID from the CLI
    let id: String
    
    /// Display title (may be nil, auto-generated from first message)
    let title: String?
    
    /// Workspace path this thread belongs to
    let cwd: String
    
    /// When the last message was sent
    let lastMessageAt: Date
    
    /// Number of messages in the thread
    let messageCount: Int
    
    /// Whether this thread is archived
    let isArchived: Bool
    
    init(
        id: String,
        title: String? = nil,
        cwd: String,
        lastMessageAt: Date = Date(),
        messageCount: Int = 0,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.lastMessageAt = lastMessageAt
        self.messageCount = messageCount
        self.isArchived = isArchived
    }
    
    /// Display title (falls back to date if no title)
    var displayTitle: String {
        title ?? lastMessageAt.formatted(date: .abbreviated, time: .shortened)
    }
}
