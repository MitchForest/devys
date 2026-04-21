import SwiftUI
import AppKit

/// Recursively renders a split node (pane or split)
struct SplitNodeView<Content: View, EmptyContent: View>: View {
    let node: SplitNode
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    var body: some View {
        switch node {
        case .pane(let paneState):
            // Wrap in NSHostingController for proper layout constraints
            SinglePaneWrapper(
                pane: paneState,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle
            )

        case .split(let splitState):
            SplitContainerView(
                splitState: splitState,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle
            )
        }
    }
}

/// Wrapper that uses NSHostingController for proper AppKit layout constraints
struct SinglePaneWrapper<Content: View, EmptyContent: View>: NSViewRepresentable {
    let pane: PaneState
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    func makeNSView(context: Context) -> NSView {
        let paneView = PaneContainerView(
            pane: pane,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle
        )
        let hostingController = NSHostingController(rootView: paneView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        let containerView = NSView()
        containerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Store hosting controller reference
        context.coordinator.hostingController = hostingController

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Always update rootView to ensure closures (contentBuilder, emptyPaneBuilder) stay fresh.
        // These closures capture app-level state (like tabContents) that may change.
        // SwiftUI will efficiently diff the view thanks to @Observable PaneState -
        // only the changed parts will re-render, not the entire content tree.
        //
        // Note: The re-render optimization is in SplitContainerView, which checks node identity
        // before updating child hosting views. This prevents sibling panes from re-rendering
        // when a split is created or modified.
        let paneView = PaneContainerView(
            pane: pane,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle
        )
        context.coordinator.hostingController?.rootView = paneView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var hostingController: NSHostingController<PaneContainerView<Content, EmptyContent>>?
    }
}
