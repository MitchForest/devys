import Foundation
import CodeEditSourceEditor
import CodeEditLanguages

// MARK: - Open File

/// Represents a single open file in the code editor.
public struct OpenFile: Identifiable, Equatable {
    /// Unique identifier for this open file instance
    public let id: UUID

    /// File URL on disk
    public let url: URL

    /// Current content of the file
    public var content: String

    /// Whether the file has unsaved changes
    public var isDirty: Bool

    /// Current cursor line (1-based)
    public var cursorLine: Int

    /// Current cursor column (1-based)
    public var cursorColumn: Int

    /// Detected programming language
    public var language: CodeLanguage

    // MARK: - Computed Properties

    /// File name
    public var name: String {
        url.lastPathComponent
    }

    /// Display name with dirty indicator
    public var displayName: String {
        isDirty ? "• \(name)" : name
    }

    /// File extension
    public var fileExtension: String {
        url.pathExtension.lowercased()
    }

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        url: URL,
        content: String = "",
        isDirty: Bool = false,
        cursorLine: Int = 1,
        cursorColumn: Int = 1,
        language: CodeLanguage? = nil
    ) {
        self.id = id
        self.url = url
        self.content = content
        self.isDirty = isDirty
        self.cursorLine = cursorLine
        self.cursorColumn = cursorColumn
        self.language = language ?? CodeLanguage.detectFromExtension(url.pathExtension)
    }

    /// Create from file URL, loading content from disk
    public static func load(from url: URL) throws -> OpenFile {
        let content = try String(contentsOf: url, encoding: .utf8)
        return OpenFile(url: url, content: content)
    }
}

// MARK: - Code Editor State

/// State for a code editor pane supporting multiple open files.
public struct CodeEditorState: Equatable, Hashable {
    /// All open files in this editor pane
    public var openFiles: [OpenFile]

    /// ID of the currently active file
    public var activeFileId: UUID?

    // MARK: - Computed Properties

    /// The currently active file
    public var activeFile: OpenFile? {
        guard let id = activeFileId else { return nil }
        return openFiles.first { $0.id == id }
    }

    /// Index of the active file
    public var activeFileIndex: Int? {
        guard let id = activeFileId else { return nil }
        return openFiles.firstIndex { $0.id == id }
    }

    /// Whether any file has unsaved changes
    public var hasUnsavedChanges: Bool {
        openFiles.contains { $0.isDirty }
    }

    /// Number of open files
    public var fileCount: Int {
        openFiles.count
    }

    /// Whether there are any open files
    public var hasOpenFiles: Bool {
        !openFiles.isEmpty
    }

    // MARK: - Initialization

    public init() {
        self.openFiles = []
        self.activeFileId = nil
    }

    /// Create with a single file open
    public init(fileURL: URL? = nil, content: String = "") {
        if let url = fileURL {
            let file = OpenFile(url: url, content: content)
            self.openFiles = [file]
            self.activeFileId = file.id
        } else {
            self.openFiles = []
            self.activeFileId = nil
        }
    }

    // MARK: - File Operations

    /// Open a file (or switch to it if already open)
    public mutating func openFile(_ url: URL, content: String) {
        // Check if already open
        if let existing = openFiles.first(where: { $0.url == url }) {
            activeFileId = existing.id
            return
        }

        let file = OpenFile(url: url, content: content)
        openFiles.append(file)
        activeFileId = file.id
    }

    /// Close a file by ID
    public mutating func closeFile(_ id: UUID) {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else { return }

        let wasActive = activeFileId == id
        openFiles.remove(at: index)

        // Update active file if needed
        if wasActive {
            if openFiles.isEmpty {
                activeFileId = nil
            } else if index < openFiles.count {
                activeFileId = openFiles[index].id
            } else {
                activeFileId = openFiles.last?.id
            }
        }
    }

    /// Switch to a file by ID
    public mutating func switchToFile(_ id: UUID) {
        guard openFiles.contains(where: { $0.id == id }) else { return }
        activeFileId = id
    }

    /// Update the content of a file
    public mutating func updateContent(_ id: UUID, content: String) {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else { return }
        if openFiles[index].content != content {
            openFiles[index].content = content
            openFiles[index].isDirty = true
        }
    }

    /// Update cursor position for a file
    public mutating func updateCursor(_ id: UUID, line: Int, column: Int) {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else { return }
        openFiles[index].cursorLine = line
        openFiles[index].cursorColumn = column
    }

    /// Mark a file as saved
    public mutating func markSaved(_ id: UUID) {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else { return }
        openFiles[index].isDirty = false
    }

    /// Save a file to disk
    public mutating func saveFile(_ id: UUID) throws {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else { return }
        let file = openFiles[index]
        try file.content.write(to: file.url, atomically: true, encoding: .utf8)
        openFiles[index].isDirty = false
    }

    /// Save all dirty files
    public mutating func saveAllFiles() throws {
        for index in openFiles.indices where openFiles[index].isDirty {
            try openFiles[index].content.write(
                to: openFiles[index].url,
                atomically: true,
                encoding: .utf8
            )
            openFiles[index].isDirty = false
        }
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(openFiles.map(\.id))
        hasher.combine(activeFileId)
    }
}

// MARK: - Language Detection

extension CodeLanguage {
    /// Detect language from file extension
    public static func detectFromExtension(_ ext: String) -> CodeLanguage {
        switch ext.lowercased() {
        case "swift": return .swift
        case "js": return .javascript
        case "jsx": return .jsx
        case "ts": return .typescript
        case "tsx": return .tsx
        case "py", "python": return .python
        case "rb", "ruby": return .ruby
        case "go": return .go
        case "rs", "rust": return .rust
        case "c": return .c
        case "cpp", "cc", "cxx": return .cpp
        case "h", "hpp": return .cpp
        case "m": return .objc
        case "java": return .java
        case "kt", "kts": return .kotlin
        case "html", "htm": return .html
        case "css": return .css
        case "scss", "sass": return .css
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "toml": return .toml
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh": return .bash
        case "sql": return .sql
        case "php": return .php
        case "lua": return .lua
        case "dart": return .dart
        case "dockerfile": return .dockerfile
        default: return .default
        }
    }
}
