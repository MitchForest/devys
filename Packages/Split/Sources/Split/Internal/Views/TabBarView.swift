import SwiftUI
import UniformTypeIdentifiers
import UI

/// Tab bar view with scrollable tabs, drag/drop support, and split buttons
struct TabBarView: View {
    @Environment(DevysSplitController.self) private var controller
    @Environment(SplitViewController.self) private var splitViewController
    @Environment(\.splitColors) private var colors
    
    @Bindable var pane: PaneState
    let isFocused: Bool
    var showSplitButtons: Bool = true

    @State private var dropTargetIndex: Int?
    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var canScrollLeft: Bool {
        scrollOffset > 1
    }

    private var canScrollRight: Bool {
        contentWidth > containerWidth && scrollOffset < contentWidth - containerWidth - 1
    }

    /// Whether this tab bar should show full saturation (focused or drag source)
    private var shouldShowFullSaturation: Bool {
        isFocused || splitViewController.dragSourcePaneId == pane.id
    }

    private var layoutMetrics: TabBarLayoutMetrics {
        controller.configuration.appearance.layoutMetrics
    }

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tabs with fade overlays
            GeometryReader { containerGeo in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: layoutMetrics.tabSpacing) {
                            ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { index, tab in
                                tabItem(for: tab, at: index)
                                    .id(tab.id)
                            }

                            // Drop zone at end of tabs
                            dropZoneAtEnd
                        }
                        .padding(.horizontal, TabBarMetrics.barPadding)
                        .background(
                            GeometryReader { contentGeo in
                                Color.clear
                                    .onChange(of: contentGeo.frame(in: .named("tabScroll"))) { _, newFrame in
                                        scrollOffset = -newFrame.minX
                                        contentWidth = newFrame.width
                                    }
                                    .onAppear {
                                        let frame = contentGeo.frame(in: .named("tabScroll"))
                                        scrollOffset = -frame.minX
                                        contentWidth = frame.width
                                    }
                            }
                        )
                    }
                    .contentShape(Rectangle())
                    .onDrop(of: [.text], delegate: appendDropDelegate)
                    .coordinateSpace(name: "tabScroll")
                    .onAppear {
                        containerWidth = containerGeo.size.width
                        if let tabId = pane.selectedTabId {
                            proxy.scrollTo(tabId, anchor: .center)
                        }
                    }
                    .onChange(of: containerGeo.size.width) { _, newWidth in
                        containerWidth = newWidth
                    }
                    .onChange(of: pane.selectedTabId) { _, newTabId in
                        if let tabId = newTabId {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(tabId, anchor: .center)
                            }
                        }
                    }
                }
                .frame(height: layoutMetrics.barHeight)
                .overlay(fadeOverlays)
            }

            Spacer()

            // Split buttons
            if showSplitButtons {
                splitButtons
            }
        }
        .frame(height: layoutMetrics.barHeight)
        .contentShape(Rectangle())
        .background(tabBarBackground)
        .saturation(shouldShowFullSaturation ? 1.0 : 0)
    }

    // MARK: - Tab Item

    @ViewBuilder
    private func tabItem(for tab: TabItem, at index: Int) -> some View {
        TabItemView(
            tab: tab,
            isSelected: pane.selectedTabId == tab.id,
            layoutMetrics: layoutMetrics,
            onSelect: {
                withAnimation(.easeInOut(duration: TabBarMetrics.selectionDuration)) {
                    pane.selectTab(tab.id)
                    controller.focusPane(pane.id)
                }
            },
            onClose: {
                withAnimation(.easeInOut(duration: TabBarMetrics.closeDuration)) {
                    _ = controller.closeTab(TabID(id: tab.id), inPane: pane.id)
                }
            }
        )
        .onDrag {
            createItemProvider(for: tab)
        } preview: {
            TabDragPreview(tab: tab, layoutMetrics: layoutMetrics)
        }
        .onDrop(of: [.text], delegate: TabDropDelegate(
            targetIndex: index,
            pane: pane,
            splitController: controller,
            dropTargetIndex: $dropTargetIndex
        ))
        .overlay(alignment: .leading) {
            if dropTargetIndex == index {
                dropIndicator
            }
        }
    }

    // MARK: - Item Provider

    private func createItemProvider(for tab: TabItem) -> NSItemProvider {
        // Set drag source for visual feedback
        splitViewController.draggingTab = tab
        splitViewController.dragSourcePaneId = pane.id

        let transfer = TabTransferData(tab: tab, sourcePaneId: pane.id.id)
        if let data = try? JSONEncoder().encode(transfer),
           let string = String(data: data, encoding: .utf8) {
            return NSItemProvider(object: string as NSString)
        }
        return NSItemProvider()
    }

    private var appendDropDelegate: TabDropDelegate {
        TabDropDelegate(
            targetIndex: pane.tabs.count,
            pane: pane,
            splitController: controller,
            dropTargetIndex: $dropTargetIndex
        )
    }

    // MARK: - Drop Zone at End

    @ViewBuilder
    private var dropZoneAtEnd: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 30, height: layoutMetrics.tabHeight)
            .contentShape(Rectangle())
            .onDrop(of: [.text], delegate: appendDropDelegate)
            .overlay(alignment: .leading) {
                if dropTargetIndex == pane.tabs.count {
                    dropIndicator
                }
            }
    }

    // MARK: - Drop Indicator

    @ViewBuilder
    private var dropIndicator: some View {
        InsertionIndicator(color: colors.accent)
            .offset(x: -1)
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Split Buttons

    @ViewBuilder
    private var splitButtons: some View {
        HStack(spacing: 4) {
            Button {
                // 120fps animation handled by SplitAnimator
                controller.dispatchGestureIntent(
                    .splitPane(
                        paneID: pane.id,
                        orientation: .horizontal,
                        insertion: .after
                    )
                )
            } label: {
                Icon("square.split.2x1", size: .sm)
            }
            .buttonStyle(.borderless)
            .help("Split Right")

            Button {
                // 120fps animation handled by SplitAnimator
                controller.dispatchGestureIntent(
                    .splitPane(
                        paneID: pane.id,
                        orientation: .vertical,
                        insertion: .after
                    )
                )
            } label: {
                Icon("square.split.1x2", size: .sm)
            }
            .buttonStyle(.borderless)
            .help("Split Down")
        }
        .padding(.trailing, 8)
    }

    // MARK: - Fade Overlays

    @ViewBuilder
    private var fadeOverlays: some View {
        let fadeWidth: CGFloat = 24

        HStack(spacing: 0) {
            // Left fade
            LinearGradient(
                colors: [colors.tabBarBackground, colors.tabBarBackground.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
            .opacity(canScrollLeft ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: canScrollLeft)
            .allowsHitTesting(false)

            Spacer()

            // Right fade
            LinearGradient(
                colors: [colors.tabBarBackground.opacity(0), colors.tabBarBackground],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
            .opacity(canScrollRight ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: canScrollRight)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var tabBarBackground: some View {
        Rectangle()
            .fill(isFocused ? colors.tabBarBackground : colors.tabBarBackground.opacity(0.95))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(colors.separator)
                    .frame(height: 1)
            }
    }
}

// MARK: - Tab Drop Delegate

struct TabDropDelegate: DropDelegate {
    let targetIndex: Int
    let pane: PaneState
    let splitController: DevysSplitController
    @Binding var dropTargetIndex: Int?

    func performDrop(info: DropInfo) -> Bool {
        dropTargetIndex = nil

        guard let provider = info.itemProviders(for: [.text]).first else {
            clearDragState()
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let string = Self.extractString(from: item)
            DispatchQueue.main.async {
                handleLoadedItem(string)
            }
        }

        return true
    }

    private func handleLoadedItem(_ string: String?) {
        clearDragState()
        guard let string,
              let transfer = decodeTransfer(from: string) else {
            return
        }

        if transfer.sourcePaneId == pane.id.id {
            reorderTab(transfer)
        } else {
            transferTab(transfer)
        }
    }

    nonisolated private static func extractString(from item: NSSecureCoding?) -> String? {
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        if let nsString = item as? NSString {
            return nsString as String
        }
        if let str = item as? String {
            return str
        }
        return nil
    }

    private func reorderTab(_ transfer: TabTransferData) {
        guard let sourceIndex = pane.tabs.firstIndex(where: { $0.id == transfer.tab.id }) else {
            return
        }
        _ = withAnimation(.spring(
            duration: TabBarMetrics.reorderDuration,
            bounce: TabBarMetrics.reorderBounce
        )) {
            splitController.dispatchGestureIntent(
                .reorderTab(
                    tabID: TabID(id: transfer.tab.id),
                    paneID: pane.id,
                    sourceIndex: sourceIndex,
                    destinationIndex: targetIndex
                )
            )
        }
    }

    private func transferTab(_ transfer: TabTransferData) {
        guard let sourcePane = splitController.internalController.rootNode.findPane(
            PaneID(id: transfer.sourcePaneId)
        ),
        let sourceIndex = sourcePane.tabs.firstIndex(where: { $0.id == transfer.tab.id }) else {
            return
        }
        let sourcePaneID = sourcePane.id
        _ = withAnimation(.spring(
            duration: TabBarMetrics.reorderDuration,
            bounce: TabBarMetrics.reorderBounce
        )) {
            splitController.dispatchGestureIntent(
                .moveTab(
                    tabID: TabID(id: transfer.tab.id),
                    sourcePaneID: sourcePaneID,
                    sourceIndex: sourceIndex,
                    destinationPaneID: pane.id,
                    destinationIndex: targetIndex
                )
            )
        }
    }

    private func clearDragState() {
        splitController.internalController.draggingTab = nil
        splitController.internalController.dragSourcePaneId = nil
    }

    func dropEntered(info: DropInfo) {
        dropTargetIndex = targetIndex
    }

    func dropExited(info: DropInfo) {
        if dropTargetIndex == targetIndex {
            dropTargetIndex = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    private func decodeTransfer(from string: String) -> TabTransferData? {
        guard let data = string.data(using: .utf8),
              let transfer = try? JSONDecoder().decode(TabTransferData.self, from: data) else {
            return nil
        }
        return transfer
    }
}
