// DevysCore.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// DevysCore provides the foundational data models and services
/// for workspace management, file system operations, and panel state.
///
/// ## Overview
/// This package contains:
/// - **Workspace**: Multi-workspace management with persistence
/// - **FileSystem**: File tree models, file watching, and file operations
/// - **Panels**: Panel content and state models
///
/// ## Architecture
/// All models follow the Observation pattern (@Observable classes)
/// or are simple Codable structs for persistence.
public enum DevysCore {
    /// Current version of the DevysCore package.
    public static let version = "1.0.0"
}
