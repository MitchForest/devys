// WorkspaceManager.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation

/// Manages the lifecycle of workspaces including CRUD operations and persistence.
///
/// The WorkspaceManager is the single source of truth for all workspace data
/// and handles saving/loading from persistent storage.
@MainActor
@Observable
public final class WorkspaceManager {
    // MARK: - Properties
    
    /// All available workspaces, sorted by last opened date.
    public private(set) var workspaces: [Workspace] = []
    
    /// The currently active workspace.
    public var currentWorkspace: Workspace? {
        didSet {
            if let workspace = currentWorkspace {
                updateLastOpened(workspace)
            }
        }
    }
    
    /// Whether the manager is currently loading.
    public private(set) var isLoading = false
    
    // MARK: - Private Properties
    
    private let persistenceKey = "devys.workspaces"
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    /// Creates a new workspace manager and loads persisted workspaces.
    public init() {
        loadWorkspaces()
    }
    
    // MARK: - Public Methods
    
    /// Creates a new workspace from a folder URL.
    /// - Parameter folderURL: The root folder URL for the workspace.
    /// - Returns: The newly created workspace.
    @discardableResult
    public func createWorkspace(from folderURL: URL) -> Workspace {
        let name = folderURL.lastPathComponent
        let workspace = Workspace(name: name, path: folderURL)
        
        workspaces.insert(workspace, at: 0)
        saveWorkspaces()
        
        return workspace
    }
    
    /// Opens an existing workspace, updating its last opened timestamp.
    /// - Parameter workspace: The workspace to open.
    public func openWorkspace(_ workspace: Workspace) {
        currentWorkspace = workspace
    }
    
    /// Deletes a workspace from the manager.
    /// - Parameter workspace: The workspace to delete.
    /// - Note: This does not delete the actual folder, only the workspace reference.
    public func deleteWorkspace(_ workspace: Workspace) {
        workspaces.removeAll { $0.id == workspace.id }
        
        if currentWorkspace?.id == workspace.id {
            currentWorkspace = workspaces.first
        }
        
        saveWorkspaces()
    }
    
    /// Renames a workspace.
    /// - Parameters:
    ///   - workspace: The workspace to rename.
    ///   - newName: The new name for the workspace.
    public func renameWorkspace(_ workspace: Workspace, to newName: String) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else {
            return
        }
        
        workspaces[index].name = newName
        
        if currentWorkspace?.id == workspace.id {
            currentWorkspace?.name = newName
        }
        
        saveWorkspaces()
    }
    
    /// Updates the panel layout for a workspace.
    /// - Parameters:
    ///   - workspace: The workspace to update.
    ///   - layout: The new panel layout.
    public func updateLayout(for workspace: Workspace, layout: PanelLayout) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else {
            return
        }
        
        workspaces[index].panelLayout = layout
        
        if currentWorkspace?.id == workspace.id {
            currentWorkspace?.panelLayout = layout
        }
        
        saveWorkspaces()
    }
    
    // MARK: - Private Methods
    
    private func updateLastOpened(_ workspace: Workspace) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else {
            return
        }
        
        workspaces[index].lastOpened = Date()
        sortWorkspaces()
        saveWorkspaces()
    }
    
    private func sortWorkspaces() {
        workspaces.sort { $0.lastOpened > $1.lastOpened }
    }
    
    private func loadWorkspaces() {
        isLoading = true
        defer { isLoading = false }
        
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            workspaces = try decoder.decode([Workspace].self, from: data)
            sortWorkspaces()
            
            // Validate that workspace folders still exist
            workspaces = workspaces.filter { workspace in
                fileManager.fileExists(atPath: workspace.path.path)
            }
        } catch {
            print("Failed to load workspaces: \(error)")
            workspaces = []
        }
    }
    
    private func saveWorkspaces() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(workspaces)
            UserDefaults.standard.set(data, forKey: persistenceKey)
        } catch {
            print("Failed to save workspaces: \(error)")
        }
    }
}
