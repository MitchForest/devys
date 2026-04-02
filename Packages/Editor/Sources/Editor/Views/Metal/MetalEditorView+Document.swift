// MetalEditorView+Document.swift
// DevysEditor

#if os(macOS)
import Foundation
import MetalKit
import Syntax
import Rendering

extension MetalEditorView {
    // MARK: - Document

    func documentDidChange() {
        guard let document = document else {
            resetDocumentState()
            return
        }

        configureLineBuffer(for: document)
        loadThemeColors()
        startHighlighting(for: document)
    }

    private func resetDocumentState() {
        lineBuffer = nil
        highlightEngine = nil
        backgroundHighlightTask?.cancel()
        backgroundHighlightTask = nil
    }

    private func configureLineBuffer(for document: EditorDocument) {
        lineBuffer = LineBuffer(document: document, metrics: metrics)
        lineBuffer?.viewportHeight = bounds.height
    }

    private func startHighlighting(for document: EditorDocument) {
        Task { @MainActor in
            backgroundHighlightTask?.cancel()
            backgroundHighlightTask = nil
            let engine = await HighlightEngine(
                language: document.language,
                themeName: self.configuration.themeName
            )
            self.highlightEngine = engine
            await highlightVisibleLines(document: document, engine: engine)
        }
    }

    func highlightVisibleLines(
        document: EditorDocument,
        engine: HighlightEngine
    ) async {
        lineBuffer?.updateVisibleRange()
        guard let visibleRange = lineBuffer?.visibleRange else {
            metalEditorLogger.error("No tokenization range available")
            return
        }

        let lines = document.lines(in: visibleRange)
        guard !lines.isEmpty else { return }

        isHighlighting = true
        let highlighted = await engine.highlightLines(
            lines,
            startingAt: visibleRange.lowerBound
        )
        isHighlighting = false

        logHighlightDebug(highlighted, visibleRange: visibleRange)
        applyHighlightedLines(highlighted)
        scheduleBackgroundHighlight()
    }

    private func applyHighlightedLines(_ highlighted: [HighlightedLine]) {
        cachedHighlightedLines.removeAll()
        for line in highlighted {
            cachedHighlightedLines[line.lineIndex] = line
        }
    }

    private func logHighlightDebug(_ highlighted: [HighlightedLine], visibleRange: Range<Int>) {
        #if DEBUG
        let highlightedCount = highlighted.count
        let rangeDescription = String(describing: visibleRange)
        metalEditorLogger.debug("Cached highlighted lines: \(highlightedCount, privacy: .public)")
        metalEditorLogger.debug("Cached highlight range: \(rangeDescription, privacy: .public)")
        if let first = highlighted.first {
            let linePreview = String(first.text.prefix(30))
            let tokenCount = first.tokens.count
            metalEditorLogger.debug("First line index: \(first.lineIndex, privacy: .public)")
            metalEditorLogger.debug("First line preview: '\(linePreview, privacy: .public)...'")
            metalEditorLogger.debug("First line token count: \(tokenCount, privacy: .public)")
            for (i, token) in first.tokens.prefix(3).enumerated() {
                let tokenRange = String(describing: token.range)
                metalEditorLogger.debug(
                    "Token \(i, privacy: .public) range: \(tokenRange, privacy: .public)"
                )
                metalEditorLogger.debug(
                    "Token \(i, privacy: .public) fg: \(token.foregroundColor, privacy: .public)"
                )
            }
        }
        #endif
    }

    /// Load colors based on configuration
    private func loadThemeColors() {
        if configuration.useDevysColors {
            loadDevysColors()
        } else {
            loadShikiThemeColors()
        }
    }

    /// Load colors from DevysColors design system
    private func loadDevysColors() {
        let palette = configuration.colorScheme == .light ? Self.devysColorsLight : Self.devysColorsDark

        backgroundColor = palette.bg0
        foregroundColor = palette.text
        lineNumberColor = palette.textTertiary
        cursorColor = palette.accent
        selectionColor = palette.accentMuted

        // Set clear color (Metal expects linear values here too since we use _srgb format)
        mtkView.clearColor = MTLClearColor(
            red: Double(backgroundColor.x),
            green: Double(backgroundColor.y),
            blue: Double(backgroundColor.z),
            alpha: 1.0
        )
    }

    /// Load colors from Shiki theme
    private func loadShikiThemeColors() {
        do {
            let theme = try ShikiTheme.load(name: configuration.themeName)

            // Background
            if let bgHex = theme.editorBackground {
                backgroundColor = hexToLinearColor(bgHex)
                mtkView.clearColor = MTLClearColor(
                    red: Double(backgroundColor.x),
                    green: Double(backgroundColor.y),
                    blue: Double(backgroundColor.z),
                    alpha: 1.0
                )
            }

            // Foreground
            if let fgHex = theme.editorForeground {
                foregroundColor = hexToLinearColor(fgHex)
            }

            // Line numbers
            if let lnHex = theme.colors?["editorLineNumber.foreground"] {
                lineNumberColor = hexToLinearColor(lnHex)
            }

            // Cursor
            if let cursorHex = theme.cursorColor {
                cursorColor = hexToLinearColor(cursorHex)
            }

            // Selection
            if let selHex = theme.selectionBackground {
                selectionColor = hexToLinearColor(selHex)
            }
        } catch {
            let themeName = configuration.themeName
            metalEditorLogger.error(
                "Failed to load theme \(themeName, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            // Fallback to DevysColors
            loadDevysColors()
        }
    }

    /// Highlight visible lines asynchronously
    func highlightVisibleLines() async {
        guard !isHighlighting,
              let document = document,
              let lineBuffer = lineBuffer,
              let engine = highlightEngine else {
            return
        }

        isHighlighting = true
        defer { isHighlighting = false }

        _ = await processHighlightBatch(
            document: document,
            lineBuffer: lineBuffer,
            engine: engine
        )
    }

    private func processHighlightBatch(
        document: EditorDocument,
        lineBuffer: LineBuffer,
        engine: HighlightEngine
    ) async -> Bool {
        lineBuffer.updateVisibleRange()
        let visibleRange = lineBuffer.visibleRange
        let tokenRange = lineBuffer.tokenizationRange

        guard let batch = nextHighlightBatch(
            document: document,
            visibleRange: visibleRange,
            tokenRange: tokenRange
        ) else {
            return false
        }

        let highlighted = await engine.highlightLines(
            batch.lines,
            startingAt: batch.start
        )

        for line in highlighted {
            cachedHighlightedLines[line.lineIndex] = line
        }

        return true
    }

    private func nextHighlightBatch(
        document: EditorDocument,
        visibleRange: Range<Int>,
        tokenRange: Range<Int>
    ) -> (start: Int, lines: [String])? {
        guard tokenRange.lowerBound < tokenRange.upperBound else { return nil }

        let visibleMissing = missingLines(in: visibleRange)
        let startCandidate: Int?

        if let firstVisible = visibleMissing.first {
            startCandidate = firstVisible
        } else if let firstTokenMissing = missingLines(in: tokenRange).first {
            startCandidate = firstTokenMissing
        } else {
            return nil
        }

        guard var start = startCandidate else { return nil }
        if start > tokenRange.lowerBound,
           cachedHighlightedLines[start - 1] == nil {
            if let cached = nearestCachedLine(before: start, in: tokenRange) {
                start = cached + 1
            } else {
                start = tokenRange.lowerBound
            }
        }

        let end = min(start + highlightBatchSize, tokenRange.upperBound)
        guard start < end else { return nil }

        let lines = document.lines(in: start..<end)
        guard !lines.isEmpty else { return nil }

        return (start: start, lines: lines)
    }

    private func missingLines(in range: Range<Int>) -> [Int] {
        var result: [Int] = []
        for lineIndex in range where cachedHighlightedLines[lineIndex] == nil {
            result.append(lineIndex)
        }
        return result
    }

    private func nearestCachedLine(before index: Int, in range: Range<Int>) -> Int? {
        guard index > range.lowerBound else { return nil }
        var candidate = index - 1
        while candidate >= range.lowerBound {
            if cachedHighlightedLines[candidate] != nil {
                return candidate
            }
            if candidate == range.lowerBound { break }
            candidate -= 1
        }
        return nil
    }

    private func scheduleBackgroundHighlight() {
        backgroundHighlightTask?.cancel()
        backgroundHighlightTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let document,
                      let lineBuffer,
                      let engine = highlightEngine else {
                    return
                }

                if isHighlighting {
                    await Task.yield()
                    continue
                }

                isHighlighting = true
                let didWork = await processHighlightBatch(
                    document: document,
                    lineBuffer: lineBuffer,
                    engine: engine
                )
                isHighlighting = false

                if !didWork {
                    return
                }

                await Task.yield()
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    func configurationDidChange() {
        guard let device = mtkView.device else { return }

        metrics = EditorMetrics.measure(
            fontSize: configuration.fontSize,
            fontName: configuration.fontName
        )

        glyphAtlas = EditorGlyphAtlas(
            device: device,
            fontName: configuration.fontName,
            fontSize: configuration.fontSize,
            scaleFactor: scaleFactor
        )

        lineBuffer?.metrics = metrics

        // Load theme colors
        loadThemeColors()

        // Reload highlight engine with new theme
        if let document = document {
            Task { @MainActor in
                backgroundHighlightTask?.cancel()
                backgroundHighlightTask = nil
                highlightEngine = await HighlightEngine(
                    language: document.language,
                    themeName: configuration.themeName
                )
                cachedHighlightedLines.removeAll()
                await highlightVisibleLines()
                scheduleBackgroundHighlight()
            }
        }
    }
}

#endif
