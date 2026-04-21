import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Internal drop zone positions for creating splits
enum PaneDropZone: Equatable {
    case center
    case left
    case right
    case top
    case bottom

    var orientation: SplitOrientation? {
        switch self {
        case .left, .right: return .horizontal
        case .top, .bottom: return .vertical
        case .center: return nil
        }
    }

    var insertion: SplitInsertionPosition {
        switch self {
        case .left, .top:
            return .before
        default:
            return .after
        }
    }
}

/// Container for a single pane with its tab bar and content area
struct PaneContainerView<Content: View, EmptyContent: View>: View {
    @Environment(\.splitColors) private var colors
    @Environment(DevysSplitController.self) private var splitController
    @Environment(SplitViewController.self) private var controller
    
    @Bindable var pane: PaneState
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    @State private var activeDropZone: PaneDropZone?

    private var isFocused: Bool {
        controller.focusedPaneId == pane.id
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            TabBarView(
                pane: pane,
                isFocused: isFocused,
                showSplitButtons: showSplitButtons
            )

            // Content area with drop zones
            contentAreaWithDropZones
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: colors.paneCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: colors.paneCornerRadius, style: .continuous)
                .strokeBorder(colors.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        .padding(colors.paneGap / 2)
        .background(colors.baseBackground)
    }

    // MARK: - Content Area with Drop Zones

    @ViewBuilder
    private var contentAreaWithDropZones: some View {
        GeometryReader { geometry in
            let size = geometry.size

            let content = contentArea
                .frame(width: size.width, height: size.height)

            if splitController.configuration.acceptedDropTypes.isEmpty {
                content
                    .overlay {
                        ZStack {
                            internalDropReceiver(for: size)
                            dropPlaceholder(for: activeDropZone, in: size)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                content
                    .onDrop(
                        of: splitController.configuration.acceptedDropTypes,
                        delegate: UnifiedPaneDropDelegate(
                            size: size,
                            pane: pane,
                            controller: controller,
                            splitController: splitController,
                            activeDropZone: $activeDropZone
                        )
                    )
                    .overlay {
                        ZStack {
                            internalDropReceiver(for: size)
                            dropPlaceholder(for: activeDropZone, in: size)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .clipped()
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if pane.tabs.isEmpty {
            emptyPaneView
        } else {
            switch contentViewLifecycle {
            case .recreateOnSwitch:
                // Original behavior: only render selected tab
                if let selectedTab = pane.selectedTab {
                    contentBuilder(selectedTab, pane.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

            case .keepAllAlive:
                // macOS-like behavior: keep all tab views in hierarchy
                ZStack {
                    ForEach(pane.tabs) { tab in
                        contentBuilder(tab, pane.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(tab.id == pane.selectedTabId ? 1 : 0)
                            .allowsHitTesting(tab.id == pane.selectedTabId)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func internalDropReceiver(for size: CGSize) -> some View {
        // Only mount the overlay while a tab drag is active so it does not block
        // the pane's interactive content, but make the decision from the observed
        // environment controller so drag state changes trigger a view update.
        if controller.draggingTab != nil && controller.dragSourcePaneId != nil {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onDrop(of: [.text], delegate: UnifiedPaneDropDelegate(
                    size: size,
                    pane: pane,
                    controller: controller,
                    splitController: splitController,
                    activeDropZone: $activeDropZone
                ))
        }
    }

    // MARK: - Drop Placeholder

    @ViewBuilder
    private func dropPlaceholder(for zone: PaneDropZone?, in size: CGSize) -> some View {
        let placeholderColor = colors.accent.opacity(0.25)
        let borderColor = colors.accent
        let padding: CGFloat = 4

        let frame = dropPlaceholderFrame(for: zone, in: size, padding: padding)

        RoundedRectangle(cornerRadius: colors.paneCornerRadius, style: .continuous)
            .fill(placeholderColor)
            .overlay(
                RoundedRectangle(cornerRadius: colors.paneCornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 2)
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .opacity(zone != nil ? 1 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.15), value: zone)
    }

    private func dropPlaceholderFrame(
        for zone: PaneDropZone?,
        in size: CGSize,
        padding: CGFloat
    ) -> CGRect {
        switch zone {
        case .center, .none:
            return CGRect(
                x: padding,
                y: padding,
                width: size.width - padding * 2,
                height: size.height - padding * 2
            )
        case .left:
            return CGRect(
                x: padding,
                y: padding,
                width: size.width / 2 - padding,
                height: size.height - padding * 2
            )
        case .right:
            return CGRect(
                x: size.width / 2,
                y: padding,
                width: size.width / 2 - padding,
                height: size.height - padding * 2
            )
        case .top:
            return CGRect(
                x: padding,
                y: padding,
                width: size.width - padding * 2,
                height: size.height / 2 - padding
            )
        case .bottom:
            return CGRect(
                x: padding,
                y: size.height / 2,
                width: size.width - padding * 2,
                height: size.height / 2 - padding
            )
        }
    }

    // MARK: - Empty Pane View

    @ViewBuilder
    private var emptyPaneView: some View {
        emptyPaneBuilder(pane.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Unified Pane Drop Delegate

struct UnifiedPaneDropDelegate: DropDelegate {
    let size: CGSize
    let pane: PaneState
    let controller: SplitViewController
    let splitController: DevysSplitController
    @Binding var activeDropZone: PaneDropZone?
    
    /// Internal drags are only valid when DevysSplit has active tab drag state.
    private var isInternalTabDrag: Bool {
        controller.draggingTab != nil && controller.dragSourcePaneId != nil
    }

    /// External types exclude `.text`, which is reserved for internal tab transfer.
    private var externalAcceptedTypes: [UTType] {
        splitController.configuration.acceptedDropTypes
    }

    private final class URLCollector: @unchecked Sendable {
        private var urls: [URL] = []
        private let lock = NSLock()

        func append(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        func snapshot() -> [URL] {
            lock.lock()
            let value = urls
            lock.unlock()
            return value
        }
    }

    // Calculate zone based on position within the view
    private func zoneForLocation(_ location: CGPoint) -> PaneDropZone {
        let edgeRatio: CGFloat = 0.25
        let horizontalEdge = max(80, size.width * edgeRatio)
        let verticalEdge = max(80, size.height * edgeRatio)

        // Check edges first (left/right take priority at corners)
        if location.x < horizontalEdge {
            return .left
        } else if location.x > size.width - horizontalEdge {
            return .right
        } else if location.y < verticalEdge {
            return .top
        } else if location.y > size.height - verticalEdge {
            return .bottom
        } else {
            return .center
        }
    }
    
    /// Convert internal PaneDropZone to public DropZone
    private func toPublicDropZone(_ zone: PaneDropZone) -> DropZone {
        switch zone {
        case .center:
            return .center
        case .left, .right:
            return .edge(
                orientation: .horizontal,
                insertion: zone.insertion
            )
        case .top, .bottom:
            return .edge(
                orientation: .vertical,
                insertion: zone.insertion
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let zone = zoneForLocation(info.location)
        activeDropZone = nil

        if isInternalTabDrag {
            guard let textProvider = info.itemProviders(for: [.text]).first else {
                controller.draggingTab = nil
                controller.dragSourcePaneId = nil
                return false
            }
            return handleInternalTabDrop(provider: textProvider, zone: zone)
        }

        return handleExternalDrop(info: info, zone: zone)
    }
    
    // MARK: - Internal Tab Drop
    
    private func handleInternalTabDrop(provider: NSItemProvider, zone: PaneDropZone) -> Bool {
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let string = Self.extractString(from: item)
            DispatchQueue.main.async {
                // Clear drag state
                controller.draggingTab = nil
                controller.dragSourcePaneId = nil

                guard let string, let transfer = decodeTransfer(from: string) else {
                    return
                }

                // Find source pane
                guard let sourcePaneId = controller.rootNode.allPaneIds.first(
                    where: { $0.id == transfer.sourcePaneId }
                ) else {
                    return
                }

                if zone == .center {
                    // Drop in center - move tab to this pane
                    guard let sourcePane = controller.rootNode.findPane(sourcePaneId),
                          let sourceIndex = sourcePane.tabs.firstIndex(where: { $0.id == transfer.tab.id }) else {
                        return
                    }
                    _ = withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                        splitController.dispatchGestureIntent(
                            .moveTab(
                                tabID: TabID(id: transfer.tab.id),
                                sourcePaneID: sourcePaneId,
                                sourceIndex: sourceIndex,
                                destinationPaneID: pane.id,
                                destinationIndex: nil
                            )
                        )
                    }
                } else if let orientation = zone.orientation {
                    // Drop on edge - create a split with the dragged tab.
                    guard let sourcePane = controller.rootNode.findPane(sourcePaneId),
                          let sourceIndex = sourcePane.tabs.firstIndex(where: { $0.id == transfer.tab.id }) else {
                        return
                    }
                    _ = withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                        splitController.dispatchGestureIntent(
                            .splitTab(
                                tabID: TabID(id: transfer.tab.id),
                                sourcePaneID: sourcePaneId,
                                sourceIndex: sourceIndex,
                                targetPaneID: pane.id,
                                orientation: orientation,
                                insertion: zone.insertion
                            )
                        )
                    }
                }
            }
        }
        return true
    }
    
    // MARK: - External Drop
    
    private func handleExternalDrop(
        info: DropInfo,
        zone: PaneDropZone
    ) -> Bool {
        let publicPaneId = PaneID(id: pane.id.id)
        let publicZone = toPublicDropZone(zone)

        let droppedTypes = info.itemProviders(for: externalAcceptedTypes).compactMap { provider -> UTType? in
            for type in externalAcceptedTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                return type
            }
            return nil
        }

        guard !droppedTypes.isEmpty else { return false }

        if splitController.delegate?.splitView(
            splitController,
            shouldAcceptDrop: droppedTypes,
            inPane: publicPaneId
        ) == false {
            return false
        }

        if info.hasItemsConforming(to: [.fileURL]) {
            return handleFileURLDrop(
                info: info,
                publicPaneId: publicPaneId,
                publicZone: publicZone
            )
        }

        for customType in externalAcceptedTypes {
            if customType == .fileURL { continue } // Already handled
            if info.hasItemsConforming(to: [customType]) {
                return handleCustomTypeDrop(
                    info: info,
                    type: customType,
                    publicPaneId: publicPaneId,
                    publicZone: publicZone
                )
            }
        }
        
        return false
    }
    
    private func handleFileURLDrop(
        info: DropInfo,
        publicPaneId: PaneID,
        publicZone: DropZone
    ) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        let collectedURLs = URLCollector()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                if let data = item as? Data,
                   let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString) {
                    collectedURLs.append(url)
                } else if let url = item as? URL {
                    collectedURLs.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let loadedURLs = collectedURLs.snapshot()
            guard !loadedURLs.isEmpty else { return }

            let content = DropContent.files(loadedURLs)
            self.deliverDropToDelegate(
                content: content,
                publicPaneId: publicPaneId,
                publicZone: publicZone
            )
        }
        
        return true
    }
    
    private func handleCustomTypeDrop(
        info: DropInfo,
        type: UTType,
        publicPaneId: PaneID,
        publicZone: DropZone
    ) -> Bool {
        guard let provider = info.itemProviders(for: [type]).first else { return false }
        
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            DispatchQueue.main.async {
                guard let data else { return }
                
                let content = DropContent.custom(type: type, data: data)
                self.deliverDropToDelegate(
                    content: content,
                    publicPaneId: publicPaneId,
                    publicZone: publicZone
                )
            }
        }
        
        return true
    }
    
    private func deliverDropToDelegate(
        content: DropContent,
        publicPaneId: PaneID,
        publicZone: DropZone
    ) {
        _ = splitController.delegate?.splitView(
            splitController,
            didReceiveDrop: content,
            inPane: publicPaneId,
            zone: publicZone
        )
    }

    func dropEntered(info: DropInfo) {
        activeDropZone = zoneForLocation(info.location)
    }

    func dropExited(info: DropInfo) {
        activeDropZone = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        activeDropZone = zoneForLocation(info.location)
        return DropProposal(operation: isInternalTabDrag ? .move : .copy)
    }

    func validateDrop(info: DropInfo) -> Bool {
        if isInternalTabDrag {
            return info.hasItemsConforming(to: [.text])
        }

        for type in externalAcceptedTypes where info.hasItemsConforming(to: [type]) {
            return true
        }
        return false
    }

    private func decodeTransfer(from string: String) -> TabTransferData? {
        guard let data = string.data(using: .utf8),
              let transfer = try? JSONDecoder().decode(TabTransferData.self, from: data) else {
            return nil
        }
        return transfer
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
}
