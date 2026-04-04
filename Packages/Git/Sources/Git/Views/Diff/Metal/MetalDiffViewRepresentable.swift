// MetalDiffViewRepresentable.swift
// SwiftUI wrapper for Metal diff renderer.

#if os(macOS)
import SwiftUI
import Rendering
import Syntax

@MainActor
struct MetalDiffViewRepresentable: NSViewRepresentable {
    let layout: DiffRenderLayout
    let theme: DiffTheme
    let themeName: String
    let language: String
    let configuration: DiffRenderConfiguration
    let syntaxHighlightingEnabled: Bool
    let maxHighlightLineLength: Int
    let syntaxBacklogPolicy: SyntaxBacklogPolicy
    @Binding var scrollOffset: CGPoint
    @Binding var splitRatio: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollOffset: $scrollOffset, splitRatio: $splitRatio)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MetalDiffScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !configuration.wrapLines
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        // Enable smooth scrolling features
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.usesPredominantAxisScrolling = true

        let documentView = MetalDiffDocumentView(frame: .zero)
        documentView.updateConfiguration(configuration)
        documentView.updateTheme(theme, themeName: themeName)
        documentView.updateLanguage(language)
        documentView.updateLayout(layout)
        documentView.updateHighlighting(
            enabled: syntaxHighlightingEnabled,
            maxLineLength: maxHighlightLineLength,
            backlogPolicy: syntaxBacklogPolicy
        )
        documentView.updateSplitRatio(splitRatio)
        documentView.onSplitRatioChanged = { newRatio in
            context.coordinator.splitRatio.wrappedValue = newRatio
        }

        scrollView.documentView = documentView
        context.coordinator.attach(to: scrollView)
        context.coordinator.scrollOffset = $scrollOffset
        context.coordinator.splitRatio = $splitRatio
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        nsView.hasHorizontalScroller = !configuration.wrapLines
        nsView.hasVerticalScroller = true

        if let documentView = nsView.documentView as? MetalDiffDocumentView {
            documentView.updateConfiguration(configuration)
            documentView.updateTheme(theme, themeName: themeName)
            documentView.updateLanguage(language)
            documentView.updateLayout(layout)
            documentView.updateHighlighting(
                enabled: syntaxHighlightingEnabled,
                maxLineLength: maxHighlightLineLength,
                backlogPolicy: syntaxBacklogPolicy
            )
            documentView.updateSplitRatio(splitRatio)
            documentView.onSplitRatioChanged = { newRatio in
                context.coordinator.splitRatio.wrappedValue = newRatio
            }
        }
        context.coordinator.attach(to: nsView)
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var observedClipView: NSClipView?
        var scrollOffset: Binding<CGPoint>
        var splitRatio: Binding<CGFloat>

        init(scrollOffset: Binding<CGPoint>, splitRatio: Binding<CGFloat>) {
            self.scrollOffset = scrollOffset
            self.splitRatio = splitRatio
        }

        func attach(to scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            if observedClipView === clipView {
                return
            }

            if let observedClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedClipView
                )
            }

            observedClipView = clipView
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
            scrollOffset.wrappedValue = clipView.bounds.origin
        }

        @objc private func handleBoundsDidChange(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView else { return }
            scrollOffset.wrappedValue = clipView.bounds.origin
        }
    }
}

final class MetalDiffScrollView: NSScrollView {
    // Let NSScrollView handle scrolling natively for:
    // - Momentum scrolling (inertia after finger lifts)
    // - Rubber-banding/elasticity at boundaries
    // - Smooth acceleration curves
    // - Proper scroll event coalescing
    //
    // We only configure the scroll view properly in the representable.
}
#endif
