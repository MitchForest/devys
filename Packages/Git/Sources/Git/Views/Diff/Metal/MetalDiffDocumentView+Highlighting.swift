// MetalDiffDocumentView+Highlighting.swift

#if os(macOS)
import AppKit
import Rendering

extension MetalDiffDocumentView {
    func tokens(for content: String) -> [HighlightToken]? {
        guard !content.isEmpty else { return [] }
        guard syntaxHighlightingEnabled else { return nil }
        if maxHighlightLineLength > 0, content.utf16.count > maxHighlightLineLength {
            return nil
        }
        let key = HighlightKey(content: content, language: language, themeName: themeName)
        if let cached = highlightCache[key] {
            return cached
        }

        if !pendingHighlights.contains(key) {
            pendingHighlights.insert(key)
            highlightQueue.append(key)
            startHighlightTaskIfNeeded()
        }
        return nil
    }

    func startHighlightTaskIfNeeded() {
        guard highlightTask == nil else { return }
        let engine = highlightEngine
        highlightTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !self.highlightQueue.isEmpty {
                if Task.isCancelled { break }
                let batchCount = min(self.highlightBatchSize, self.highlightQueue.count)
                let batch = Array(self.highlightQueue.prefix(batchCount))
                self.highlightQueue.removeFirst(batchCount)

                var results: [(HighlightKey, [HighlightToken])] = []
                results.reserveCapacity(batch.count)

                for key in batch {
                    if Task.isCancelled { break }
                    let tokens = await engine.highlight(
                        line: key.content,
                        language: key.language,
                        themeName: key.themeName
                    )
                    results.append((key, tokens))
                }

                for (key, tokens) in results {
                    self.highlightCache[key] = tokens
                    self.pendingHighlights.remove(key)
                }

                await Task.yield()
            }
            self.highlightTask = nil
        }
    }

    func resetHighlights() {
        highlightTask?.cancel()
        highlightTask = nil
        highlightQueue.removeAll()
        highlightCache.removeAll()
        pendingHighlights.removeAll()
    }

    func textForToken(_ token: HighlightToken, in text: String) -> String {
        let tokenStart = token.range.lowerBound
        let tokenEnd = min(token.range.upperBound, text.utf16.count)
        let startIdx = text.utf16Index(at: tokenStart)
        let endIdx = text.utf16Index(at: tokenEnd)
        return String(text[startIdx..<endIdx])
    }

    func tokenFlags(_ token: HighlightToken) -> UInt32 {
        var flags: UInt32 = 0
        if token.fontStyle.contains(.bold) { flags |= EditorCellFlags.bold.rawValue }
        if token.fontStyle.contains(.italic) { flags |= EditorCellFlags.italic.rawValue }
        return flags
    }
}
#endif
