// MetalDiffDocumentView+TextRendering.swift

#if os(macOS)
// periphery:ignore:all - resolved diff packets are consumed by Metal draw paths
import Foundation
import Rendering
import Syntax

struct ResolvedDiffDisplayText: Sendable, Equatable {
    let packet: ResolvedTextRenderPacket
    let syntaxStatus: HighlightStatus?

    // periphery:ignore - retained for future diff diagnostics overlays
    var countsAsActualHighlight: Bool {
        syntaxStatus?.countsAsActual == true
    }

    // periphery:ignore - retained for future diff diagnostics overlays
    var isSyntaxTracked: Bool {
        syntaxStatus != nil
    }
}

struct ResolvedVisibleUnifiedDiffDisplayRow: Identifiable, Sendable, Equatable {
    let rowIndex: Int
    let id: String
    let kind: UnifiedDiffRow.Kind
    let lineType: DiffLine.LineType
    let oldLineNumberPacket: ResolvedTextRenderPacket?
    let newLineNumberPacket: ResolvedTextRenderPacket?
    let prefixPacket: ResolvedTextRenderPacket?
    let content: ResolvedDiffDisplayText
}

struct ResolvedSplitDiffDisplaySide: Sendable, Equatable {
    let lineType: DiffLine.LineType
    let lineNumberPacket: ResolvedTextRenderPacket?
    let content: ResolvedDiffDisplayText
}

struct ResolvedVisibleSplitDiffDisplayRow: Identifiable, Sendable, Equatable {
    let rowIndex: Int
    let id: String
    let kind: SplitDiffRow.Kind
    let headerPacket: ResolvedTextRenderPacket?
    let left: ResolvedSplitDiffDisplaySide?
    let right: ResolvedSplitDiffDisplaySide?
}

struct ResolvedUnifiedDiffDisplaySnapshot: Sendable, Equatable {
    // periphery:ignore - retained for viewport diagnostics and snapshot symmetry
    let visibleRowRange: ClosedRange<Int>
    let rows: [ResolvedVisibleUnifiedDiffDisplayRow]
}

struct ResolvedSplitDiffDisplaySnapshot: Sendable, Equatable {
    // periphery:ignore - retained for viewport diagnostics and snapshot symmetry
    let visibleRowRange: ClosedRange<Int>
    let rows: [ResolvedVisibleSplitDiffDisplayRow]
}

enum ResolvedDiffDisplaySnapshot: Sendable, Equatable {
    case unified(ResolvedUnifiedDiffDisplaySnapshot)
    case split(ResolvedSplitDiffDisplaySnapshot)
}

extension MetalDiffDocumentView {
    func resolve(_ snapshot: DiffDisplaySnapshot) -> ResolvedDiffDisplaySnapshot {
        switch snapshot {
        case .unified(let unified):
            return .unified(
                ResolvedUnifiedDiffDisplaySnapshot(
                    visibleRowRange: unified.visibleRowRange,
                    rows: unified.rows.map(resolveUnifiedRow)
                )
            )
        case .split(let split):
            return .split(
                ResolvedSplitDiffDisplaySnapshot(
                    visibleRowRange: split.visibleRowRange,
                    rows: split.rows.map(resolveSplitRow)
                )
            )
        }
    }

    private func resolveUnifiedRow(_ row: VisibleUnifiedDiffDisplayRow) -> ResolvedVisibleUnifiedDiffDisplayRow {
        ResolvedVisibleUnifiedDiffDisplayRow(
            rowIndex: row.rowIndex,
            id: row.id,
            kind: row.kind,
            lineType: row.lineType,
            oldLineNumberPacket: row.oldLineNumberPacket.map(glyphAtlas.resolve),
            newLineNumberPacket: row.newLineNumberPacket.map(glyphAtlas.resolve),
            prefixPacket: row.prefixPacket.map(glyphAtlas.resolve),
            content: resolveDisplayText(row.content)
        )
    }

    private func resolveSplitRow(_ row: VisibleSplitDiffDisplayRow) -> ResolvedVisibleSplitDiffDisplayRow {
        ResolvedVisibleSplitDiffDisplayRow(
            rowIndex: row.rowIndex,
            id: row.id,
            kind: row.kind,
            headerPacket: row.headerPacket.map(glyphAtlas.resolve),
            left: row.left.map(resolveSplitSide),
            right: row.right.map(resolveSplitSide)
        )
    }

    private func resolveSplitSide(_ side: SplitDiffDisplaySide) -> ResolvedSplitDiffDisplaySide {
        ResolvedSplitDiffDisplaySide(
            lineType: side.lineType,
            lineNumberPacket: side.lineNumberPacket.map(glyphAtlas.resolve),
            content: resolveDisplayText(side.content)
        )
    }

    private func resolveDisplayText(_ text: DiffDisplayText) -> ResolvedDiffDisplayText {
        ResolvedDiffDisplayText(
            packet: glyphAtlas.resolve(text.packet),
            syntaxStatus: text.syntaxStatus
        )
    }

    func renderPacket(
        _ packet: ResolvedTextRenderPacket,
        origin: SIMD2<Float>,
        metrics: RenderMetrics,
        maxX: Float?
    ) {
        var cursorX = origin.x
        let limit = maxX ?? Float.greatestFiniteMagnitude

        for cell in packet.cells {
            if cursorX + metrics.cellWidth > limit { return }
            cellBuffer.addCell(
                EditorCellGPU(
                    position: SIMD2(cursorX, origin.y),
                    foregroundColor: cell.foregroundColor,
                    backgroundColor: cell.backgroundColor,
                    uvOrigin: cell.uvOrigin,
                    uvSize: cell.uvSize,
                    flags: cell.flags
                )
            )
            cursorX += metrics.cellWidth
        }
    }
}

#endif
