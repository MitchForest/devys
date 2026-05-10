import CoreGraphics
import Metal

public enum GhosttyTerminalRendererWarmup {
    @MainActor
    @discardableResult
    public static func prepareSharedResources(
        scaleFactor: CGFloat = 2
    ) throws -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return false
        }

        _ = try GhosttyTerminalRendererSharedResources.shared(
            device: device,
            fontMetrics: GhosttyTerminalFontMetrics.default(),
            scaleFactor: max(scaleFactor, 1)
        )
        return true
    }
}
