// Ported from the reference repo's TerminalSurface host layer (P0-014).
// IME-lite text input: enough NSTextInputClient to route committed text
// and dead-key composition; full marked-text rendering is out of scope.

import Foundation
import TerminalSurfaceCore
import TerminalVT

#if os(macOS)
    import AppKit

    extension GhosttyTerminalHostView: @preconcurrency NSTextInputClient {
        func hasMarkedText() -> Bool {
            markedText.length > 0
        }

        func markedRange() -> NSRange {
            guard hasMarkedText() else { return NSRange(location: NSNotFound, length: 0) }
            return NSRange(location: 0, length: markedText.length)
        }

        func selectedRange() -> NSRange {
            NSRange(location: NSNotFound, length: 0)
        }

        func setMarkedText(
            _ string: Any,
            selectedRange _: NSRange,
            replacementRange _: NSRange
        ) {
            switch string {
            case let attributedString as NSAttributedString:
                markedText = NSMutableAttributedString(attributedString: attributedString)
            case let string as String:
                markedText = NSMutableAttributedString(string: string)
            default:
                markedText = NSMutableAttributedString()
            }
            needsDisplay = true
        }

        func unmarkText() {
            markedText = NSMutableAttributedString()
            needsDisplay = true
        }

        func validAttributesForMarkedText() -> [NSAttributedString.Key] {
            []
        }

        func attributedSubstring(
            forProposedRange range: NSRange,
            actualRange: NSRangePointer?
        ) -> NSAttributedString? {
            guard range.location != NSNotFound,
                  range.location < markedText.length else {
                actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
                return nil
            }
            let length = min(range.length, markedText.length - range.location)
            let actual = NSRange(location: range.location, length: length)
            actualRange?.pointee = actual
            return markedText.attributedSubstring(from: actual)
        }

        func characterIndex(for point: NSPoint) -> Int {
            guard let grid = gridMetrics() else { return 0 }
            let converted = convert(point, from: nil)
            let cell = grid.clampedCell(for: terminalContentPoint(from: converted))
            return cell.row * grid.cols + cell.col
        }

        func firstRect(
            forCharacterRange _: NSRange,
            actualRange: NSRangePointer?
        ) -> NSRect {
            actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
            let cursorRect = imeCursorRect()
            guard let window else { return cursorRect }
            return window.convertToScreen(convert(cursorRect, to: nil))
        }

        func insertText(_ string: Any, replacementRange _: NSRange) {
            let text: String
            switch string {
            case let attributedString as NSAttributedString:
                text = attributedString.string
            case let string as String:
                text = string
            default:
                return
            }

            unmarkText()
            if var accumulator = keyTextAccumulator {
                accumulator.append(text)
                keyTextAccumulator = accumulator
            } else if let event = NSApp.currentEvent,
                      let command = TerminalMacInputAdapter.command(for: event, text: text) {
                callbacks.onInput(command)
            }
        }

        override func doCommand(by _: Selector) {}

        static func shouldSuppressComposingControlInput(_ text: String?, composing: Bool) -> Bool {
            guard composing, let text else { return false }
            let scalars = text.unicodeScalars
            guard let scalar = scalars.first,
                  scalars.index(after: scalars.startIndex) == scalars.endIndex else {
                return false
            }
            return scalar.value < 0x20
        }

        private func imeCursorRect() -> NSRect {
            guard let grid = gridMetrics() else {
                return NSRect(x: bounds.minX, y: bounds.minY, width: 0, height: 0)
            }
            let state = renderSession?.surfaceState ?? TerminalSurfaceState(cols: 1, rows: 1)
            let col = max(0, min(grid.cols - 1, state.cursor.col))
            let row = max(0, min(grid.rows - 1, state.cursor.row))
            let rect = grid.rect(row: row, colStart: col, colEnd: col)
            return rect.offsetBy(dx: terminalContentRect.minX, dy: terminalContentRect.minY)
        }
    }
#endif
