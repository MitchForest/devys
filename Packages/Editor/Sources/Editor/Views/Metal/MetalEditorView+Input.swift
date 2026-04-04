// MetalEditorView+Input.swift
// DevysEditor

#if os(macOS)
import AppKit
import Rendering
import Syntax
import Text

extension MetalEditorView {
    // MARK: - Input

    public override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let document, let position = textPosition(for: event) else { return }

        if event.modifierFlags.contains(.shift) {
            extendSelection(to: position)
        } else {
            document.cursor.position = position
            document.cursor.preferredColumn = nil
            document.selection = nil
            selectionAnchor = position
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let document, let anchor = selectionAnchor, let position = textPosition(for: event) else { return }
        document.cursor.position = position
        document.selection = TextRange(start: anchor, end: position)
    }

    public override func mouseUp(with event: NSEvent) {
        guard let document, let selection = document.selection else { return }
        if selection.isEmpty {
            document.selection = nil
        }
    }

    public override func keyDown(with event: NSEvent) {
        guard let document else { return }

        if handleMovementKeys(event, document: document) { return }
        if handleEditingKeys(event, document: document) { return }

        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            super.keyDown(with: event)
            return
        }

        if let text = event.characters, !text.isEmpty {
            insertText(text, document: document)
            return
        }

        super.keyDown(with: event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers else {
            return false
        }

        switch chars.lowercased() {
        case "c":
            copy(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "a":
            selectAll(nil)
            return true
        default:
            return false
        }
    }

    // MARK: - Save Actions

    @objc public func saveDocument(_ _: Any?) {
        guard let document else {
            NSSound.beep()
            return
        }
        if let url = document.fileURL {
            saveDocument(to: url)
        } else {
            saveDocumentAs(nil)
        }
    }

    @objc public func saveDocumentAs(_ _: Any?) {
        guard let document else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = document.fileURL?.lastPathComponent ?? "Untitled"
        panel.message = "Save file"
        panel.prompt = "Save"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveDocument(to: url)
    }

    private func saveDocument(to url: URL) {
        guard let document else { return }
        let content = document.content
        Task { @MainActor in
            do {
                let io = DefaultDocumentIOService()
                try await io.save(content: content, to: url)
                document.fileURL = url
                document.isDirty = false
                onDocumentURLChange?(url)
            } catch {
                metalEditorLogger.error("Failed to save file: \(String(describing: error), privacy: .public)")
                NSSound.beep()
            }
        }
    }

    @objc public func copy(_ _: Any?) {
        guard let document, let selection = document.selection, !selection.isEmpty else { return }
        let text = document.text(in: selection)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc public func paste(_ _: Any?) {
        guard let document else { return }
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        insertText(text, document: document)
    }

    @objc public func cut(_ _: Any?) {
        guard let document else { return }
        copy(nil)
        if let selection = document.selection, !selection.isEmpty {
            let normalized = selection.normalized
            document.delete(selection)
            registerDocumentEdit(startLine: normalized.start.line)
        }
    }

    @objc public override func selectAll(_ sender: Any?) {
        guard let document else { return }
        let start = TextPosition(line: 0, column: 0)
        let end = document.endPosition
        document.selection = TextRange(start: start, end: end)
        selectionAnchor = start
    }

    private func handleMovementKeys(_ event: NSEvent, document: EditorDocument) -> Bool {
        let extendSelection = event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case 123: // left
            moveCursor(document: document, extendSelection: extendSelection) {
                document.moveCursorLeft()
            }
            return true
        case 124: // right
            moveCursor(document: document, extendSelection: extendSelection) {
                document.moveCursorRight()
            }
            return true
        case 126: // up
            moveCursor(document: document, extendSelection: extendSelection) {
                document.moveCursorUp()
            }
            return true
        case 125: // down
            moveCursor(document: document, extendSelection: extendSelection) {
                document.moveCursorDown()
            }
            return true
        case 115: // home
            moveCursor(document: document, extendSelection: extendSelection) {
                document.moveCursorToLineStart()
            }
            return true
        case 119: // end
            moveCursor(document: document, extendSelection: extendSelection) {
                document.moveCursorToLineEnd()
            }
            return true
        default:
            return false
        }
    }

    private func handleEditingKeys(_ event: NSEvent, document: EditorDocument) -> Bool {
        switch event.keyCode {
        case 51: // backspace
            handleBackspace(document: document)
            return true
        case 117: // delete
            handleForwardDelete(document: document)
            return true
        case 36, 76: // return / enter
            insertText("\n", document: document)
            return true
        case 48: // tab
            let text = configuration.insertSpacesForTab
                ? String(repeating: " ", count: configuration.tabWidth)
                : "\t"
            insertText(text, document: document)
            return true
        default:
            return false
        }
    }

    private func handleBackspace(document: EditorDocument) {
        let lineBeforeDelete = document.cursor.position.line
        if let selection = document.selection, !selection.isEmpty {
            deleteSelection(selection, document: document)
            return
        }

        document.deleteBackward()
        registerDocumentEdit(startLine: min(document.cursor.position.line, lineBeforeDelete))
    }

    private func handleForwardDelete(document: EditorDocument) {
        let lineBeforeDelete = document.cursor.position.line
        if let selection = document.selection, !selection.isEmpty {
            deleteSelection(selection, document: document)
            return
        }

        let oldEndLine = document.cursor.position.column == document.lineLength(at: lineBeforeDelete)
            ? min(lineBeforeDelete + 1, max(0, document.lineCount - 1))
            : lineBeforeDelete
        document.deleteForward()
        registerDocumentEdit(startLine: min(lineBeforeDelete, oldEndLine))
    }

    private func deleteSelection(_ selection: TextRange, document: EditorDocument) {
        let normalized = selection.normalized
        document.delete(selection)
        registerDocumentEdit(startLine: normalized.start.line)
    }

    private func insertText(_ text: String, document: EditorDocument) {
        let startLine: Int

        if let selection = document.selection, !selection.isEmpty {
            let normalized = selection.normalized
            startLine = normalized.start.line
            document.replace(selection, with: text)
        } else {
            startLine = document.cursor.position.line
            document.insert(text)
        }

        registerDocumentEdit(startLine: startLine)
    }

    private func registerDocumentEdit(startLine: Int) {
        document?.syncSyntaxController(dirtyFrom: startLine)
        backgroundHighlightTask?.cancel()
        backgroundHighlightTask = nil
        visibleEditGeneration += 1
        pendingVisibleEditIdentifier = "editor-edit-\(visibleEditGeneration)"
        if let pendingVisibleEditIdentifier {
            SyntaxRuntimeDiagnostics.beginVisibleEdit(
                surface: "editor",
                identifier: pendingVisibleEditIdentifier
            )
        }

        highlightVisibleLines()
        scheduleBackgroundHighlight()
    }

    private func moveCursor(document: EditorDocument, extendSelection: Bool, move: () -> Void) {
        if extendSelection {
            if selectionAnchor == nil {
                if let selection = document.selection {
                    selectionAnchor = selection.normalized.start
                } else {
                    selectionAnchor = document.cursor.position
                }
            }
            move()
            if let anchor = selectionAnchor {
                document.selection = TextRange(start: anchor, end: document.cursor.position)
            }
        } else {
            move()
            document.selection = nil
            selectionAnchor = nil
        }
    }

    private func extendSelection(to position: TextPosition) {
        guard let document else { return }
        if selectionAnchor == nil {
            selectionAnchor = document.cursor.position
        }
        document.cursor.position = position
        if let anchor = selectionAnchor {
            document.selection = TextRange(start: anchor, end: position)
        }
    }

    private func textPosition(for event: NSEvent) -> TextPosition? {
        let point = convert(event.locationInWindow, from: nil)
        let flippedY = bounds.height - point.y
        guard let document, let lineBuffer else { return nil }
        let line = min(max(metrics.lineAt(y: flippedY + lineBuffer.scrollOffset), 0), document.lineCount - 1)
        let column = min(max(metrics.columnAt(x: point.x), 0), document.lineLength(at: line))
        return TextPosition(line: line, column: column)
    }

    // MARK: - Scrolling

    public override func scrollWheel(with event: NSEvent) {
        guard let lineBuffer else { return }
        let delta = ScrollWheelNormalizer.pixelDelta(for: event, lineHeight: metrics.lineHeight)
        lastHighlightScrollDelta = delta
        shouldRecordScrollTrace = delta != 0
        lineBuffer.scroll(by: -delta)
        highlightVisibleLines()
    }

    // MARK: - First Responder

    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        true
    }
}

// MARK: - String Extension

extension String {
    func utf16Index(at offset: Int) -> String.Index {
        let utf16Index = utf16.index(utf16.startIndex, offsetBy: min(offset, utf16.count))
        return utf16Index
    }
}

#endif
