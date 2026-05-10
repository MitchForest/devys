// MetalDiffDocumentView+Scrolling.swift

#if os(macOS)
import AppKit

extension MetalDiffDocumentView {
    func observeScrollView() {
        guard let contentView = enclosingScrollView?.contentView else { return }
        contentView.postsBoundsChangedNotifications = true

        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateVisibleRect()
            }
        }

        updateVisibleRect()
    }

    func updateVisibleRect() {
        guard let scrollView = enclosingScrollView else { return }
        let visibleRect = scrollView.contentView.bounds
        lastScrollDeltaY = visibleRect.origin.y - lastVisibleOriginY
        lastVisibleOriginY = visibleRect.origin.y
        shouldRecordScrollTrace = lastScrollDeltaY != 0
        mtkView.frame = visibleRect
        updateUniforms()
        refreshSyntaxViewport()
    }
}
#endif
