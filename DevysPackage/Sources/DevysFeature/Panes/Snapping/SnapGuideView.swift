import SwiftUI

/// Renders snap guide lines on the canvas.
public struct SnapGuideView: View {
    let guides: [SnapGuide]
    @Environment(\.canvasState) private var _canvas

    // swiftlint:disable:next force_unwrapping
    private var canvas: CanvasState { _canvas! } // Safe: always injected by parent

    public init(guides: [SnapGuide]) {
        self.guides = guides
    }

    public var body: some View {
        GeometryReader { geometry in
            ForEach(guides) { guide in
                guideLine(for: guide, viewportSize: geometry.size)
            }
        }
    }

    @ViewBuilder
    private func guideLine(for guide: SnapGuide, viewportSize: CGSize) -> some View {
        let color = guideColor(for: guide.type)

        switch guide.axis {
        case .horizontal:
            // Horizontal line (fixed Y)
            let y = canvas.screenPoint(
                from: CGPoint(x: 0, y: guide.position),
                viewportSize: viewportSize
            ).y
            let startX = canvas.screenPoint(
                from: CGPoint(x: guide.start, y: 0),
                viewportSize: viewportSize
            ).x
            let endX = canvas.screenPoint(
                from: CGPoint(x: guide.end, y: 0),
                viewportSize: viewportSize
            ).x

            Path { path in
                path.move(to: CGPoint(x: startX, y: y))
                path.addLine(to: CGPoint(x: endX, y: y))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        case .vertical:
            // Vertical line (fixed X)
            let x = canvas.screenPoint(
                from: CGPoint(x: guide.position, y: 0),
                viewportSize: viewportSize
            ).x
            let startY = canvas.screenPoint(
                from: CGPoint(x: 0, y: guide.start),
                viewportSize: viewportSize
            ).y
            let endY = canvas.screenPoint(
                from: CGPoint(x: 0, y: guide.end),
                viewportSize: viewportSize
            ).y

            Path { path in
                path.move(to: CGPoint(x: x, y: startY))
                path.addLine(to: CGPoint(x: x, y: endY))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    private func guideColor(for type: SnapGuide.SnapType) -> Color {
        switch type {
        case .edgeToEdge: return Theme.snapGuide
        case .sameLevel: return Theme.snapGuide.opacity(0.8)
        case .center: return Theme.snapGuide.opacity(0.6)
        }
    }
}
