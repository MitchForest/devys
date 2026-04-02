// EditorMetrics.swift
// DevysTextRenderer - Shared Metal text rendering
//
// Cell metrics and layout calculations.

import Foundation
import CoreText
import CoreGraphics

/// Metrics for editor cell layout
public struct EditorMetrics: Equatable, Sendable {
    /// Width of a single character cell in points
    public let cellWidth: CGFloat
    
    /// Height of a single line in points
    public let lineHeight: CGFloat
    
    /// Font size in points
    public let fontSize: CGFloat
    
    /// Baseline offset from top of cell
    public let baseline: CGFloat
    
    /// Font name
    public let fontName: String
    
    /// Width of gutter (line numbers)
    public let gutterWidth: CGFloat
    
    public init(
        cellWidth: CGFloat,
        lineHeight: CGFloat,
        fontSize: CGFloat,
        baseline: CGFloat,
        fontName: String,
        gutterWidth: CGFloat = 50
    ) {
        self.cellWidth = cellWidth
        self.lineHeight = lineHeight
        self.fontSize = fontSize
        self.baseline = baseline
        self.fontName = fontName
        self.gutterWidth = gutterWidth
    }
    
    /// Calculate metrics for a given font
    public static func measure(fontSize: CGFloat, fontName: String = "Menlo") -> EditorMetrics {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        
        // Measure "M" for cell width (monospace reference)
        let mGlyph = CTFontGetGlyphWithName(font, "M" as CFString)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, [mGlyph], &advance, 1)
        
        let cellWidth = ceil(advance.width).clamped(to: 6...100)
        
        // Line height from font metrics
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let lineHeight = ceil(ascent + descent + leading).clamped(to: 10...100)
        
        // Calculate gutter width (5 digits + padding)
        let gutterWidth = ceil(cellWidth * 5 + 16)
        
        return EditorMetrics(
            cellWidth: cellWidth,
            lineHeight: lineHeight,
            fontSize: fontSize,
            baseline: ascent,
            fontName: fontName,
            gutterWidth: gutterWidth
        )
    }
    
    /// Calculate visible line count for viewport
    public func visibleLines(for viewportHeight: CGFloat) -> Int {
        max(1, Int(ceil(viewportHeight / lineHeight)))
    }
    
    /// Y position for a line
    public func yPosition(forLine index: Int) -> CGFloat {
        CGFloat(index) * lineHeight
    }
    
    /// Line index at Y position
    public func lineAt(y: CGFloat) -> Int {
        max(0, Int(floor(y / lineHeight)))
    }
    
    /// X position for a column (accounting for gutter)
    public func xPosition(forColumn col: Int) -> CGFloat {
        gutterWidth + CGFloat(col) * cellWidth
    }
    
    /// Column at X position
    public func columnAt(x: CGFloat) -> Int {
        max(0, Int(floor((x - gutterWidth) / cellWidth)))
    }
}

// MARK: - Clamping

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
