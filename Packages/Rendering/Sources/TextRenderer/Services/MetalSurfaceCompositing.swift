// MetalSurfaceCompositing.swift
// Shared AppKit/Metal compositing support for glass-backed text renderers.

#if os(macOS)
import AppKit
import MetalKit
import QuartzCore

@MainActor
public final class GlassCapableMTKView: MTKView {
    public var drawsOpaqueBackground: Bool {
        didSet {
            applyCompositing()
        }
    }

    public override var isOpaque: Bool {
        drawsOpaqueBackground
    }

    public init(
        frame frameRect: CGRect,
        device: (any MTLDevice)?,
        drawsOpaqueBackground: Bool = true
    ) {
        self.drawsOpaqueBackground = drawsOpaqueBackground
        super.init(frame: frameRect, device: device)
        wantsLayer = true
        applyCompositing()
    }

    @available(*, unavailable)
    public required init(coder: NSCoder) {
        fatalError("Use init(frame:device:drawsOpaqueBackground:)")
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyCompositing()
    }

    public func applyCompositing() {
        layer?.isOpaque = drawsOpaqueBackground
        layer?.backgroundColor = drawsOpaqueBackground ? nil : NSColor.clear.cgColor
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.isOpaque = drawsOpaqueBackground
            metalLayer.wantsExtendedDynamicRangeContent = false
        }
    }
}

@MainActor
public enum MetalSurfaceCompositing {
    public static func apply(
        hostView: NSView,
        metalView: MTKView,
        drawsOpaqueBackground: Bool,
        opaqueClearColor: MTLClearColor
    ) {
        hostView.layer?.isOpaque = drawsOpaqueBackground
        hostView.layer?.backgroundColor = drawsOpaqueBackground ? nil : NSColor.clear.cgColor

        if let glassCapableView = metalView as? GlassCapableMTKView {
            glassCapableView.drawsOpaqueBackground = drawsOpaqueBackground
        }

        (metalView.layer as? CAMetalLayer)?.isOpaque = drawsOpaqueBackground
        metalView.layer?.backgroundColor = drawsOpaqueBackground ? nil : NSColor.clear.cgColor
        metalView.clearColor = drawsOpaqueBackground
            ? opaqueClearColor
            : MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    }
}
#endif
