import SwiftUI

/// Displays the current zoom level as a percentage.
///
/// The indicator:
/// - Shows in the bottom-right corner
/// - Fades out after inactivity
/// - Can be clicked to reset to 100%
public struct ZoomIndicator: View {
    var canvas: CanvasState

    /// Whether the indicator should be fully visible
    @State private var isVisible: Bool = true

    /// Timer to track fade-out delay
    @State private var fadeTask: Task<Void, Never>?

    /// Duration before fading out (seconds)
    private let fadeDelay: TimeInterval = 2.0

    public init(canvas: CanvasState) {
        self.canvas = canvas
    }

    public var body: some View {
        Button(action: { canvas.zoomTo100() }) {
            Text(zoomText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .onChange(of: canvas.scale) { _, _ in
            showAndScheduleFade()
        }
        .onAppear {
            showAndScheduleFade()
        }
        .help("Click to reset to 100%")
    }

    private var zoomText: String {
        let percentage = Int(round(canvas.scale * 100))
        return "\(percentage)%"
    }

    private func showAndScheduleFade() {
        // Cancel any existing fade task
        fadeTask?.cancel()

        // Show the indicator
        isVisible = true

        // Schedule fade-out
        fadeTask = Task {
            try? await Task.sleep(for: .seconds(fadeDelay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isVisible = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.2)

        VStack {
            Spacer()
            HStack {
                Spacer()
                ZoomIndicator(canvas: CanvasState())
                    .padding()
            }
        }
    }
    .frame(width: 300, height: 200)
}
