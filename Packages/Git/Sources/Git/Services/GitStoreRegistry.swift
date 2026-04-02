// GitStoreRegistry.swift
// Registry for git stores by workspace.

import Foundation

/// Registry for git stores by workspace.
/// Maintains one GitStore per workspace.
@MainActor
public final class GitStoreRegistry {
    public static let shared = GitStoreRegistry()
    
    private var stores: [UUID: GitStore] = [:]
    
    private init() {}
    
    /// Get or create a store for a workspace.
    public func store(for workspaceId: UUID, projectFolder: URL?) -> GitStore {
        if let existing = stores[workspaceId] {
            return existing
        }
        
        let store = GitStore(projectFolder: projectFolder)
        stores[workspaceId] = store
        return store
    }
    
    /// Remove a store for a workspace.
    public func removeStore(for workspaceId: UUID) {
        if let store = stores.removeValue(forKey: workspaceId) {
            store.cleanup()
        }
    }
    
    /// Remove all stores.
    public func removeAllStores() {
        for store in stores.values {
            store.cleanup()
        }
        stores.removeAll()
    }
}
