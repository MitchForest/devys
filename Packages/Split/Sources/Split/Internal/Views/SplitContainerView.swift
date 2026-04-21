import SwiftUI
import AppKit

/// Concrete view type for split children - enables proper SwiftUI diffing
/// Unlike AnyView, this preserves type information so SwiftUI can optimize re-renders
struct SplitChildView<Content: View, EmptyContent: View>: View {
    let node: SplitNode
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    let showSplitButtons: Bool
    let contentViewLifecycle: ContentViewLifecycle
    
    var body: some View {
        switch node {
        case .pane(let paneState):
            PaneContainerView(
                pane: paneState,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle
            )
        case .split(let nestedSplitState):
            SplitContainerView(
                splitState: nestedSplitState,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle
            )
        }
    }
}

/// SwiftUI wrapper around NSSplitView for native split behavior
struct SplitContainerView<Content: View, EmptyContent: View>: NSViewRepresentable {
    @Environment(DevysSplitController.self) private var devysController
    @Bindable var splitState: SplitState
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    func makeCoordinator() -> Coordinator {
        Coordinator(
            splitState: splitState,
            devysController: devysController,
            layoutMetrics: devysController.configuration.appearance.layoutMetrics
        )
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        let appearance = devysController.configuration.appearance
        configureSplitView(
            splitView,
            context: context,
            layoutMetrics: appearance.layoutMetrics
        )
        applyInitialDividerPosition(
            to: splitView,
            context: context,
            appearance: appearance
        )

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        // Update orientation if changed
        splitView.isVertical = splitState.orientation == .horizontal

        // Always update child hosting views to ensure closures stay fresh.
        // When app state changes (tabContents, terminalSessions, etc.), new closures
        // are created that reference the updated state. We must pass these to children.
        // SwiftUI will efficiently diff the view trees thanks to @Observable PaneState.
        let subviews = splitView.arrangedSubviews
        if subviews.count >= 2 {
            updateHostingView(subviews[0], for: splitState.first)
            updateHostingView(subviews[1], for: splitState.second)
        }

        let layoutMetrics = devysController.configuration.appearance.layoutMetrics
        context.coordinator.layoutMetrics = layoutMetrics

        // Access dividerPosition to ensure SwiftUI tracks this dependency
        // Then sync if the position changed externally
        let currentPosition = splitState.dividerPosition
        context.coordinator.syncPosition(currentPosition, in: splitView)
    }

    // MARK: - Helpers
    
    /// Type alias for the concrete child view used in hosting controllers
    private typealias ChildView = SplitChildView<Content, EmptyContent>

    private func makeHostingView(for node: SplitNode) -> NSView {
        let childView = makeChildView(for: node)
        let hostingController = NSHostingController(rootView: childView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        return hostingController.view
    }

    private func updateHostingView(_ view: NSView, for node: SplitNode) {
        // Use concrete type instead of AnyView for proper SwiftUI diffing
        if let hostingView = view as? NSHostingView<ChildView> {
            hostingView.rootView = makeChildView(for: node)
        }
    }
    
    private func makeChildView(for node: SplitNode) -> ChildView {
        SplitChildView(
            node: node,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle
        )
    }

    private func configureSplitView(
        _ splitView: NSSplitView,
        context: Context,
        layoutMetrics: TabBarLayoutMetrics
    ) {
        splitView.isVertical = splitState.orientation == .horizontal
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        splitView.addArrangedSubview(makeHostingView(for: splitState.first))
        splitView.addArrangedSubview(makeHostingView(for: splitState.second))

        context.coordinator.layoutMetrics = layoutMetrics
    }

    private func applyInitialDividerPosition(
        to splitView: NSSplitView,
        context: Context,
        appearance: DevysSplitConfiguration.Appearance
    ) {
        let shouldAnimate = appearance.enableAnimations && appearance.animationDuration > 0
        let animationOrigin = splitState.animationOrigin
        let newPaneIndex = animationOrigin == .fromFirst ? 0 : 1

        if animationOrigin != nil, shouldAnimate {
            // Clear immediately so we don't re-animate on updates
            splitState.animationOrigin = nil
            splitView.arrangedSubviews[newPaneIndex].isHidden = true
            context.coordinator.isAnimating = true
        }

        DispatchQueue.main.async {
            let totalSize = splitState.orientation == .horizontal
                ? splitView.bounds.width
                : splitView.bounds.height

            guard totalSize > 0 else { return }

            if animationOrigin != nil, shouldAnimate {
                animateDivider(
                    in: splitView,
                    context: context,
                    appearance: appearance,
                    totalSize: totalSize,
                    newPaneIndex: newPaneIndex,
                    animationOrigin: animationOrigin
                )
            } else if animationOrigin != nil {
                // Clear immediately so we don't re-animate on updates
                splitState.animationOrigin = nil
                splitView.arrangedSubviews[newPaneIndex].isHidden = false
                splitState.dividerPosition = 0.5
                let position = totalSize * splitState.dividerPosition
                splitView.setPosition(position, ofDividerAt: 0)
                context.coordinator.isAnimating = false
            } else {
                let position = totalSize * splitState.dividerPosition
                splitView.setPosition(position, ofDividerAt: 0)
            }
        }
    }

    private func animateDivider(
        in splitView: NSSplitView,
        context: Context,
        appearance: DevysSplitConfiguration.Appearance,
        totalSize: CGFloat,
        newPaneIndex: Int,
        animationOrigin: SplitAnimationOrigin?
    ) {
        let startPosition: CGFloat = animationOrigin == .fromFirst ? 0 : totalSize
        splitView.setPosition(startPosition, ofDividerAt: 0)
        splitView.layoutSubtreeIfNeeded()

        let targetPosition = totalSize * 0.5
        splitState.dividerPosition = 0.5

        DispatchQueue.main.async {
            splitView.arrangedSubviews[newPaneIndex].isHidden = false
            SplitAnimator.shared.animate(
                splitView: splitView,
                from: startPosition,
                to: targetPosition,
                duration: appearance.animationDuration
            ) {
                context.coordinator.isAnimating = false
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSSplitViewDelegate {
        let splitState: SplitState
        weak var devysController: DevysSplitController?
        var isAnimating = false
        var layoutMetrics: TabBarLayoutMetrics
        /// Track last applied position to detect external changes
        var lastAppliedPosition: CGFloat = 0.5
        /// Track if user is actively dragging the divider
        var isDragging = false

        init(
            splitState: SplitState,
            devysController: DevysSplitController,
            layoutMetrics: TabBarLayoutMetrics
        ) {
            self.splitState = splitState
            self.devysController = devysController
            self.layoutMetrics = layoutMetrics
            self.lastAppliedPosition = splitState.dividerPosition
        }

        /// Apply external position changes to the NSSplitView
        func syncPosition(_ statePosition: CGFloat, in splitView: NSSplitView) {
            guard !isAnimating else { return }

            // Check if position changed externally (not from user drag)
            if abs(statePosition - lastAppliedPosition) > 0.01 {
                let totalSize = splitState.orientation == .horizontal
                    ? splitView.bounds.width
                    : splitView.bounds.height

                guard totalSize > 0 else { return }

                let pixelPosition = totalSize * statePosition
                splitView.setPosition(pixelPosition, ofDividerAt: 0)
                splitView.layoutSubtreeIfNeeded()
                lastAppliedPosition = statePosition
            }
        }

        func splitViewWillResizeSubviews(_ notification: Notification) {
            // Detect if this is a user drag by checking mouse state
            if let event = NSApp.currentEvent, event.type == .leftMouseDragged {
                isDragging = true
            }
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            // Skip position updates during animation
            guard !isAnimating else { return }
            guard let splitView = notification.object as? NSSplitView else { return }

            let totalSize = splitState.orientation == .horizontal
                ? splitView.bounds.width
                : splitView.bounds.height

            guard totalSize > 0 else { return }

            if let firstSubview = splitView.arrangedSubviews.first {
                let dividerPosition = splitState.orientation == .horizontal
                    ? firstSubview.frame.width
                    : firstSubview.frame.height

                let normalizedPosition = dividerPosition / totalSize

                // Check if drag ended (mouse up)
                if let event = NSApp.currentEvent, event.type == .leftMouseUp {
                    isDragging = false
                }

                Task { @MainActor in
                    self.splitState.dividerPosition = normalizedPosition
                    self.lastAppliedPosition = normalizedPosition
                    guard let devysController = self.devysController,
                          devysController.internalController.isExternalUpdateInProgress != true else {
                        return
                    }
                    devysController.delegate?.splitView(
                        devysController,
                        didResizeSplit: self.splitState.id,
                        position: Double(normalizedPosition)
                    )
                }
            }
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            // Allow edge positions during animation
            guard !isAnimating else { return proposedMinimumPosition }
            let minimumSize = splitState.orientation == .horizontal
                ? layoutMetrics.minimumPaneWidth
                : layoutMetrics.minimumPaneHeight
            return max(proposedMinimumPosition, minimumSize)
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            // Allow edge positions during animation
            guard !isAnimating else { return proposedMaximumPosition }
            let totalSize = splitState.orientation == .horizontal
                ? splitView.bounds.width
                : splitView.bounds.height
            let minimumSize = splitState.orientation == .horizontal
                ? layoutMetrics.minimumPaneWidth
                : layoutMetrics.minimumPaneHeight
            return min(proposedMaximumPosition, totalSize - minimumSize)
        }
    }
}
