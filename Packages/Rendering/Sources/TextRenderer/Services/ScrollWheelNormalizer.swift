// ScrollWheelNormalizer.swift
// Normalizes scroll wheel deltas to match macOS scroll behavior.

#if os(macOS)
import AppKit

public enum ScrollWheelNormalizer {
    /// Returns a pixel/point delta matching NSScrollView behavior.
    /// Positive delta means scrolling down (toward later content) in a flipped coordinate system.
    public static func pixelDelta(for event: NSEvent, lineHeight: CGFloat) -> CGFloat {
        if event.hasPreciseScrollingDeltas {
            return event.scrollingDeltaY
        }
        return event.deltaY * lineHeight
    }
}
#endif
