#if os(macOS)
import AppKit
import MetalKit
import QuartzCore
import Testing
@testable import Rendering

@MainActor
@Suite("Metal Surface Compositing Tests")
struct MetalSurfaceCompositingTests {
    @Test("Glass-capable MTK view exposes opaque and glass modes")
    func glassCapableMTKViewExposesOpaqueAndGlassModes() {
        let view = GlassCapableMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())

        #expect(view.isOpaque == true)
        #expect((view.layer as? CAMetalLayer)?.isOpaque == true)

        view.drawsOpaqueBackground = false

        #expect(view.isOpaque == false)
        #expect((view.layer as? CAMetalLayer)?.isOpaque == false)
        #expect(view.layer?.backgroundColor == NSColor.clear.cgColor)
    }

    @Test("Surface compositing applies transparent clear color for glass")
    func surfaceCompositingAppliesTransparentClearColorForGlass() {
        let hostView = NSView(frame: .zero)
        hostView.wantsLayer = true
        let metalView = GlassCapableMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())

        MetalSurfaceCompositing.apply(
            hostView: hostView,
            metalView: metalView,
            drawsOpaqueBackground: false,
            opaqueClearColor: MTLClearColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        )

        #expect(hostView.layer?.isOpaque == false)
        #expect(metalView.isOpaque == false)
        #expect((metalView.layer as? CAMetalLayer)?.isOpaque == false)
        #expect(metalView.clearColor.alpha == 0)
    }
}
#endif
