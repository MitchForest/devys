// MetalDiffDocumentView+Surface.swift

#if os(macOS)
import CoreGraphics
import Foundation

extension MetalDiffDocumentView {
    func displayBackgroundColor(for color: SIMD4<Float>) -> SIMD4<Float> {
        let surface = configuration.surfaceDesign
        guard surface.usesGlassBackground else { return color }

        if color.matchesRGB(diffTheme.background) || color.matchesRGB(diffTheme.gutterBackground) {
            return transparentSurfaceColor(opacity: surface.defaultBackgroundOpacity)
        }

        if color.matchesRGB(diffTheme.hunkHeaderBackground) {
            return color.withAlpha(surface.hunkHeaderBackgroundOpacity)
        }

        return color
    }

    func displayDividerColor(_ color: SIMD4<Float>) -> SIMD4<Float> {
        let surface = configuration.surfaceDesign
        guard surface.usesGlassBackground else { return color }
        return color.withAlpha(surface.dividerOpacity)
    }

    private func transparentSurfaceColor(opacity: CGFloat) -> SIMD4<Float> {
        SIMD4<Float>(0, 0, 0, Float(opacity))
    }
}

private extension SIMD4 where Scalar == Float {
    func matchesRGB(_ other: SIMD4<Float>, tolerance: Float = 0.001) -> Bool {
        abs(x - other.x) <= tolerance &&
            abs(y - other.y) <= tolerance &&
            abs(z - other.z) <= tolerance
    }

    func withAlpha(_ alpha: CGFloat) -> SIMD4<Float> {
        SIMD4<Float>(x, y, z, Float(alpha))
    }
}
#endif
