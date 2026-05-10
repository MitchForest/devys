// DiffRenderConfiguration.swift
// Rendering configuration for Metal diff views.

import Foundation
import CoreGraphics
import UI

enum DiffChangeStyle: String, Sendable, CaseIterable {
    case fullBackground
    case gutterBars
    case minimal

    var label: String {
        switch self {
        case .fullBackground: return "Line + Rail"
        case .gutterBars: return "Gutter Bars"
        case .minimal: return "Minimal"
        }
    }
}

struct DiffRenderConfiguration: Sendable, Equatable {
    var fontName: String
    var fontSize: CGFloat
    var lineHeight: CGFloat
    var surfaceDesign: CodeSurfaceDesign
    var diffDesign: CodeDiffDesign
    var showLineNumbers: Bool
    var showPrefix: Bool
    var showWordDiff: Bool
    var wrapLines: Bool
    var changeStyle: DiffChangeStyle
    var showsHunkHeaders: Bool

    init(
        fontName: String = CodeViewDesign.fontName,
        fontSize: CGFloat = CodeViewDesign.fontSize,
        lineHeight: CGFloat = CodeViewDesign.lineHeight,
        surfaceDesign: CodeSurfaceDesign = CodeViewDesign.surfaceDesign,
        diffDesign: CodeDiffDesign = .default,
        showLineNumbers: Bool = true,
        showPrefix: Bool = true,
        showWordDiff: Bool = true,
        wrapLines: Bool = false,
        changeStyle: DiffChangeStyle = .fullBackground,
        showsHunkHeaders: Bool = true
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.surfaceDesign = surfaceDesign
        self.diffDesign = diffDesign
        self.showLineNumbers = showLineNumbers
        self.showPrefix = showPrefix
        self.showWordDiff = showWordDiff
        self.wrapLines = wrapLines
        self.changeStyle = changeStyle
        self.showsHunkHeaders = showsHunkHeaders
    }
}
