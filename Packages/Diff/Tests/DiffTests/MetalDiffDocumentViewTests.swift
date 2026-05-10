#if os(macOS)
import CoreGraphics
import QuartzCore
import Testing
import UI
@testable import Diff

@MainActor
@Suite("MetalDiffDocumentView Tests")
struct MetalDiffDocumentViewTests {
    @Test("Glass-backed diff renderer uses transparent Metal backing")
    func glassBackedDiffRendererUsesTransparentMetalBacking() {
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        view.updateConfiguration(
            DiffRenderConfiguration(surfaceDesign: CodeSurfaceDesign.glass)
        )

        #expect(view.isOpaque == false)
        #expect(view.mtkView.isOpaque == false)
        #expect((view.mtkView.layer as? CAMetalLayer)?.isOpaque == false)
        #expect(view.mtkView.clearColor.alpha == 0)
    }

    @Test("Opaque diff renderer uses theme clear color")
    func opaqueDiffRendererUsesThemeClearColor() {
        let opaqueSurface = CodeSurfaceDesign(
            usesGlassBackground: false,
            defaultBackgroundOpacity: 1,
            hunkHeaderBackgroundOpacity: 1,
            dividerOpacity: 1
        )
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        view.updateConfiguration(
            DiffRenderConfiguration(surfaceDesign: opaqueSurface)
        )

        #expect(view.isOpaque == true)
        #expect(view.mtkView.isOpaque == true)
        #expect(view.mtkView.clearColor.alpha == 1)
    }

    @Test("Glass-backed diff renderer clears only default backgrounds")
    func glassBackedDiffRendererClearsOnlyDefaultBackgrounds() {
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        view.updateConfiguration(
            DiffRenderConfiguration(surfaceDesign: CodeSurfaceDesign.glass)
        )

        #expect(view.displayBackgroundColor(for: view.diffTheme.background) == SIMD4<Float>(0, 0, 0, 0))
        #expect(view.displayBackgroundColor(for: view.diffTheme.gutterBackground) == SIMD4<Float>(0, 0, 0, 0))
        #expect(view.displayBackgroundColor(for: view.diffTheme.addedLineBackground) == view.diffTheme.addedLineBackground)
        #expect(
            view.displayBackgroundColor(for: view.diffTheme.hunkHeaderBackground).w
                == Float(CodeSurfaceDesign.glass.hunkHeaderBackgroundOpacity)
        )
    }
}
#endif
