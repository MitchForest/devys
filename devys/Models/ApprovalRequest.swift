//
//  ApprovalRequest.swift
//  devys
//
//  An approval request from the CLI.
//  Runtime only - blocks until user responds.
//

import Foundation

/// A pending approval request from the CLI.
/// The CLI is blocked waiting for our response.
struct ApprovalRequest: Identifiable, Hashable {
    let id: String
    let description: String
    let toolName: String
    
    init(id: String, description: String, toolName: String) {
        self.id = id
        self.description = description
        self.toolName = toolName
    }
}
