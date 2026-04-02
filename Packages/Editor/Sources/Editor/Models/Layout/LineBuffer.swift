// LineBuffer.swift
// DevysEditor - Metal-accelerated code editor
//
// Manages visible lines and viewport calculations.

import Foundation
import Rendering

// MARK: - Line Buffer

/// Manages visible line range and viewport calculations.
@MainActor
final class LineBuffer {
    
    // MARK: - Properties
    
    /// Document reference
    private weak var document: EditorDocument?
    
    /// Metrics for layout
    var metrics: EditorMetrics
    
    /// First visible line index
    private(set) var firstVisibleLine: Int = 0
    
    /// Last visible line index
    private(set) var lastVisibleLine: Int = 0
    
    /// Vertical scroll offset in points
    var scrollOffset: CGFloat = 0 {
        didSet {
            updateVisibleRange()
        }
    }
    
    /// Viewport height in points
    var viewportHeight: CGFloat = 0 {
        didSet {
            updateVisibleRange()
        }
    }
    
    /// Lines before/after viewport to pre-render
    var bufferLines: Int = 50
    
    // MARK: - Initialization
    
    init(document: EditorDocument, metrics: EditorMetrics) {
        self.document = document
        self.metrics = metrics
    }
    
    // MARK: - Visible Range
    
    /// Update visible line range based on scroll position
    func updateVisibleRange() {
        guard let document = document else { return }
        
        let firstLine = metrics.lineAt(y: scrollOffset)
        let lastLine = metrics.lineAt(y: scrollOffset + viewportHeight) + 1
        
        firstVisibleLine = max(0, firstLine)
        lastVisibleLine = min(document.lineCount - 1, lastLine)
    }
    
    /// Range of lines that are visible
    var visibleRange: Range<Int> {
        firstVisibleLine..<(lastVisibleLine + 1)
    }
    
    /// Range of lines to tokenize (visible + buffer)
    var tokenizationRange: Range<Int> {
        guard let document = document else { return 0..<0 }
        
        let start = max(0, firstVisibleLine - bufferLines)
        let end = min(document.lineCount, lastVisibleLine + bufferLines + 1)
        return start..<end
    }
    
    // MARK: - Layout
    
    /// Y position for a line (in viewport coordinates)
    func viewportY(forLine index: Int) -> CGFloat {
        metrics.yPosition(forLine: index) - scrollOffset
    }
    
    /// Total content height
    var contentHeight: CGFloat {
        guard let document = document else { return 0 }
        return CGFloat(document.lineCount) * metrics.lineHeight
    }
    
    /// Maximum scroll offset
    var maxScrollOffset: CGFloat {
        max(0, contentHeight - viewportHeight)
    }
    
    // MARK: - Scrolling

    /// Scroll by delta
    func scroll(by delta: CGFloat) {
        scrollOffset = max(0, min(maxScrollOffset, scrollOffset + delta))
    }
}
