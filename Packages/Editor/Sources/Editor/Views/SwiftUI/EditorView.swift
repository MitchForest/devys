// EditorView.swift
// DevysEditor - Metal-accelerated code editor
//
// SwiftUI wrapper for MetalEditorView.

#if os(macOS)
import SwiftUI
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.devys.editor", category: "EditorView")

// MARK: - Editor View

/// SwiftUI wrapper for the Metal-accelerated editor.
public struct EditorView: NSViewRepresentable {
    
    /// URL of file to edit
    private let url: URL?
    
    /// Document to render (when managed externally)
    private let document: EditorDocument?

    /// Initial content (if no URL)
    private let initialContent: String?
    
    /// Language identifier
    private let language: String?

    /// Callback for document URL changes (Save As)
    private let onDocumentURLChange: ((URL) -> Void)?

    /// Focus request counter - when incremented, the editor requests keyboard focus
    private let focusRequestID: Int

    /// Search highlights rendered in the editor overlay.
    private let searchMatches: [EditorSearchMatch]

    /// Active search match to emphasize.
    private let activeSearchMatchID: EditorSearchMatch.ID?

    /// Navigation request counter - when incremented, the editor scrolls to the target.
    private let navigationRequestID: Int

    /// Navigation target to apply when the request counter changes.
    private let navigationTarget: EditorNavigationTarget?
    
    /// Configuration from environment
    @Environment(\.editorConfiguration) private var baseConfiguration
    
    /// System color scheme
    @Environment(\.colorScheme) private var systemColorScheme
    
    // MARK: - Initialization
    
    /// Create editor for a file URL
    public init(url: URL) {
        self.url = url
        self.document = nil
        self.initialContent = nil
        self.language = nil
        self.onDocumentURLChange = nil
        self.focusRequestID = 0
        self.searchMatches = []
        self.activeSearchMatchID = nil
        self.navigationRequestID = 0
        self.navigationTarget = nil
    }

    /// Create editor with initial content
    public init(content: String, language: String = "plaintext") {
        self.url = nil
        self.document = nil
        self.initialContent = content
        self.language = language
        self.onDocumentURLChange = nil
        self.focusRequestID = 0
        self.searchMatches = []
        self.activeSearchMatchID = nil
        self.navigationRequestID = 0
        self.navigationTarget = nil
    }

    /// Create editor from an existing document
    public init(
        document: EditorDocument,
        onDocumentURLChange: ((URL) -> Void)? = nil,
        focusRequestID: Int = 0,
        searchMatches: [EditorSearchMatch] = [],
        activeSearchMatchID: EditorSearchMatch.ID? = nil,
        navigationRequestID: Int = 0,
        navigationTarget: EditorNavigationTarget? = nil
    ) {
        self.url = nil
        self.document = document
        self.initialContent = nil
        self.language = nil
        self.onDocumentURLChange = onDocumentURLChange
        self.focusRequestID = focusRequestID
        self.searchMatches = searchMatches
        self.activeSearchMatchID = activeSearchMatchID
        self.navigationRequestID = navigationRequestID
        self.navigationTarget = navigationTarget
    }
    
    /// Effective configuration with system color scheme applied
    private var effectiveConfiguration: EditorConfiguration {
        var config = baseConfiguration
        // Sync with system color scheme
        config.colorScheme = systemColorScheme == .dark ? .dark : .light
        return config
    }
    
    // MARK: - NSViewRepresentable
    
    public func makeNSView(context: Context) -> MetalEditorView {
        let view = MetalEditorView(frame: .zero)
        view.configuration = effectiveConfiguration
        view.onDocumentURLChange = onDocumentURLChange
        
        if let document {
            view.observedDocumentLoadStateRevision = document.loadStateRevision
            view.document = document
        } else {
            // Load document async
            Task { @MainActor in
                if let url = url {
                    do {
                        let document = try await EditorDocument.load(from: url)
                        view.document = document
                    } catch {
                        logger.error("Failed to load file: \(String(describing: error), privacy: .public)")
                        let document = EditorDocument(content: "// Failed to load file: \(error.localizedDescription)")
                        view.document = document
                    }
                } else if let content = initialContent {
                    let document = EditorDocument(content: content, language: language ?? "plaintext")
                    view.document = document
                }
            }
        }

        view.searchMatches = searchMatches
        view.activeSearchMatchID = activeSearchMatchID
        
        return view
    }
    
    public func updateNSView(_ nsView: MetalEditorView, context: Context) {
        // Update configuration when color scheme changes
        nsView.configuration = effectiveConfiguration
        nsView.onDocumentURLChange = onDocumentURLChange
        if let document,
           nsView.document !== document || nsView.observedDocumentLoadStateRevision != document.loadStateRevision {
            nsView.observedDocumentLoadStateRevision = document.loadStateRevision
            nsView.document = document
        }
        nsView.searchMatches = searchMatches
        nsView.activeSearchMatchID = activeSearchMatchID

        // Handle focus requests
        if focusRequestID > 0, focusRequestID != context.coordinator.lastFocusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            nsView.requestKeyboardFocus()
        }

        if navigationRequestID > 0,
           navigationRequestID != context.coordinator.lastNavigationRequestID,
           let navigationTarget {
            context.coordinator.lastNavigationRequestID = navigationRequestID
            nsView.applyNavigationTarget(navigationTarget)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        var lastFocusRequestID: Int = 0
        var lastNavigationRequestID: Int = 0
    }
}

// MARK: - Preview

#Preview {
    EditorView(content: """
    // Hello, World!
    func greet(name: String) -> String {
        return "Hello, \\(name)!"
    }
    
    let message = greet(name: "Devys")
    log(message)
    """, language: "swift")
    .frame(width: 600, height: 400)
}

#endif
