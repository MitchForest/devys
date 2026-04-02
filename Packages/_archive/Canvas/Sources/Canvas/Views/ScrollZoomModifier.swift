// ScrollZoomModifier.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import AppKit

/// Handles scroll gestures on the canvas.
///
/// - Scroll on empty canvas → pan canvas
/// - ⌘+scroll anywhere → zoom canvas toward cursor
struct ScrollZoomModifier: ViewModifier {
    var canvas: CanvasModel
    @State private var scrollMonitor: Any?
    @State private var keyMonitor: Any?

    private let zoomSensitivity: CGFloat = 0.01
    private let panSensitivity: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .onAppear {
                setupScrollMonitor()
                setupKeyMonitor()
            }
            .onDisappear {
                removeScrollMonitor()
                removeKeyMonitor()
            }
    }

    private func setupScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [canvas] event in
            handleScrollEvent(event, canvas: canvas)
            return event
        }
    }

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [canvas] event in
            guard event.modifierFlags.contains(.command) else { return event }
            switch event.charactersIgnoringModifiers {
            case "+", "=":
                canvas.zoomIn()
                return nil // consume the event
            case "-":
                canvas.zoomOut()
                return nil
            case "0":
                canvas.zoomTo100()
                return nil
            default:
                return event
            }
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleScrollEvent(_ event: NSEvent, canvas: CanvasModel) {
        guard let window = event.window,
              let contentView = window.contentView else { return }

        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        guard abs(deltaX) > 0.5 || abs(deltaY) > 0.5 else { return }

        if event.modifierFlags.contains(.command) {
            let zoomFactor = 1.0 + (deltaY * zoomSensitivity)
            let newScale = canvas.scale * zoomFactor
            let viewportSize = contentView.bounds.size
            let locationInWindow = event.locationInWindow
            let location = CGPoint(x: locationInWindow.x, y: viewportSize.height - locationInWindow.y)
            canvas.zoom(to: newScale, toward: location, viewportSize: viewportSize)
        } else {
            // Check if we're over a scrollable subview
            let locationInWindow = event.locationInWindow
            if let hitView = contentView.hitTest(locationInWindow),
               viewHasScrollableAncestor(hitView) {
                return
            }
            canvas.pan(by: CGSize(width: deltaX * panSensitivity, height: deltaY * panSensitivity))
        }
    }

    private func viewHasScrollableAncestor(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let v = current {
            if v is NSScrollView || v is NSTextView { return true }
            let typeName = String(describing: type(of: v))
            if typeName.contains("WKWebView") || typeName.contains("Terminal") { return true }
            current = v.superview
        }
        return false
    }
}

extension View {
    /// Adds scroll-wheel zoom support to the view.
    func scrollZoom(canvas: CanvasModel) -> some View {
        modifier(ScrollZoomModifier(canvas: canvas))
    }
}
