// MetalDiffDocumentView+TextRendering.swift

#if os(macOS)
import Foundation
import Rendering

struct TextRenderContext {
    let text: String
    let tokens: [HighlightToken]?
    let wordChanges: [DiffWordChange]?
    let textColor: SIMD4<Float>
    let backgroundColor: SIMD4<Float>
    let origin: SIMD2<Float>
    let metrics: MetalDiffDocumentView.RenderMetrics
    let maxX: Float?
}

private struct TextRenderState {
    var cursorX: Float
    var charOffset: Int
    let limit: Float
    let y: Float
    let metrics: MetalDiffDocumentView.RenderMetrics
    let wordBackground: (Int) -> SIMD4<Float>?
}

extension MetalDiffDocumentView {
    func renderText(_ context: TextRenderContext) {
        let wordChangeRanges = context.wordChanges ?? []
        let wordBackground: (Int) -> SIMD4<Float>? = { offset in
            for change in wordChangeRanges where change.range.contains(offset) {
                return self.wordChangeColor(for: change.type)
            }
            return nil
        }

        var state = TextRenderState(
            cursorX: context.origin.x,
            charOffset: 0,
            limit: context.maxX ?? Float.greatestFiniteMagnitude,
            y: context.origin.y,
            metrics: context.metrics,
            wordBackground: wordBackground
        )

        if let tokens = context.tokens, !tokens.isEmpty {
            renderTokenizedText(
                tokens: tokens,
                text: context.text,
                state: &state,
                defaultBackground: context.backgroundColor
            )
        } else {
            renderPlainText(
                text: context.text,
                textColor: context.textColor,
                backgroundColor: context.backgroundColor,
                state: &state
            )
        }
    }

    private func renderTokenizedText(
        tokens: [HighlightToken],
        text: String,
        state: inout TextRenderState,
        defaultBackground: SIMD4<Float>
    ) {
        for token in tokens {
            let tokenText = textForToken(token, in: text)
            let fg = token.foreground
            let bg = token.background ?? defaultBackground
            let flags = tokenFlags(token)

            for char in tokenText {
                if state.cursorX + state.metrics.cellWidth > state.limit { return }
                let entry = glyphAtlas.entry(for: char)
                let wordBg = state.wordBackground(state.charOffset) ?? bg
                cellBuffer.addCell(
                    EditorCellGPU(
                        position: SIMD2(state.cursorX, state.y),
                        foregroundColor: fg,
                        backgroundColor: wordBg,
                        uvOrigin: entry.uvOrigin,
                        uvSize: entry.uvSize,
                        flags: flags
                    )
                )
                state.cursorX += state.metrics.cellWidth
                state.charOffset += 1
            }
        }
    }

    private func renderPlainText(
        text: String,
        textColor: SIMD4<Float>,
        backgroundColor: SIMD4<Float>,
        state: inout TextRenderState
    ) {
        for char in text {
            if state.cursorX + state.metrics.cellWidth > state.limit { return }
            let entry = glyphAtlas.entry(for: char)
            let wordBg = state.wordBackground(state.charOffset) ?? backgroundColor
            cellBuffer.addCell(
                EditorCellGPU(
                    position: SIMD2(state.cursorX, state.y),
                    foregroundColor: textColor,
                    backgroundColor: wordBg,
                    uvOrigin: entry.uvOrigin,
                    uvSize: entry.uvSize,
                    flags: 0
                )
            )
            state.cursorX += state.metrics.cellWidth
            state.charOffset += 1
        }
    }
}

#endif
