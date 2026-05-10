// MetalDiffDocumentView+Interaction.swift

#if os(macOS)
import AppKit

extension MetalDiffDocumentView {
    func dividerRect() -> CGRect? {
        guard case .split = layout else { return nil }
        let visibleRect = enclosingScrollView?.contentView.bounds ?? bounds
        let visibleWidth = visibleRect.width
        let dividerX = visibleWidth * splitRatio

        return CGRect(
            x: dividerX - dividerHitZone,
            y: 0,
            width: dividerHitZone * 2 + 1,
            height: visibleRect.height
        )
    }

    func isPointInDivider(_ point: CGPoint) -> Bool {
        guard let rect = dividerRect() else { return false }
        return rect.contains(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isPointInDivider(point) {
            isDraggingDivider = true
            NSCursor.resizeLeftRight.push()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingDivider else {
            super.mouseDragged(with: event)
            return
        }

        guard case .split = layout else { return }

        let point = convert(event.locationInWindow, from: nil)
        let visibleRect = enclosingScrollView?.contentView.bounds ?? bounds
        let visibleWidth = visibleRect.width
        guard visibleWidth > 0 else { return }

        var newRatio = point.x / visibleWidth
        newRatio = max(0.2, min(0.8, newRatio))

        if abs(newRatio - splitRatio) > 0.001 {
            splitRatio = newRatio
            onSplitRatioChanged?(newRatio)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingDivider {
            isDraggingDivider = false
            NSCursor.pop()
        } else {
            super.mouseUp(with: event)
        }
    }

    func updateDividerTrackingArea() {
        if let oldArea = dividerTrackingArea {
            removeTrackingArea(oldArea)
            dividerTrackingArea = nil
        }

        guard case .split = layout else { return }

        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .activeInKeyWindow,
            .inVisibleRect
        ]

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        dividerTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isPointInDivider(point) {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        guard case .split = layout,
              let rect = dividerRect() else { return }

        addCursorRect(rect, cursor: .resizeLeftRight)
    }
}
#endif
