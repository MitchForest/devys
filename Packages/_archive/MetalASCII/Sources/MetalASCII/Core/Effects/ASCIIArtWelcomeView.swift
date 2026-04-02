// ASCIIArtWelcomeView.swift
// DevysUI - Welcome tab view with ASCII art from famous artwork
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import SwiftUI
import AppKit

// swiftlint:disable function_body_length

// MARK: - ASCII Art Welcome View

/// SwiftUI view displaying full-pane ASCII art from famous artwork or user images.
///
/// ## Usage
/// ```swift
/// ASCIIArtWelcomeView()
///     .environment(\.devysTheme, theme)
/// ```
///
/// ## Features
/// - GPU-accelerated ASCII art rendering
/// - Theme-aware accent color
/// - Cycles through enabled images
/// - Full-pane display with no overlays
public struct ASCIIArtWelcomeView: View {

    @Environment(\.devysTheme) private var theme

    /// Specific image to display (optional - uses next in cycle if nil)
    let image: AnyWelcomeImage?

    @State private var currentImage: AnyWelcomeImage?
    @State private var renderedImage: NSImage?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var lastLoadedSize: CGSize = .zero
    @State private var hasAttemptedLoad = false

    /// Create a welcome view that displays the next image in the cycle
    public init() {
        self.image = nil
    }

    /// Create a welcome view with a specific image
    public init(image: AnyWelcomeImage) {
        self.image = image
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                theme.base

                // ASCII art - full pane
                if let rendered = renderedImage {
                    Image(nsImage: rendered)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    loadingView
                } else if loadError != nil {
                    fallbackView
                }
            }
            .onAppear {
                // Delay slightly to ensure geometry is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    loadImage(size: geometry.size)
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                // Only reload if size changed significantly (more than 50px)
                let widthDiff = abs(newSize.width - lastLoadedSize.width)
                let heightDiff = abs(newSize.height - lastLoadedSize.height)
                if widthDiff > 50 || heightDiff > 50 || !hasAttemptedLoad {
                    loadImage(size: newSize)
                }
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)

            Text("Rendering ASCII art...")
                .font(.custom("JetBrains Mono", size: 12))
                .foregroundStyle(theme.textSecondary)
        }
    }

    // MARK: - Fallback View

    private var fallbackView: some View {
        VStack(spacing: 16) {
            Text("◇")
                .font(.system(size: 48))
                .foregroundStyle(theme.textTertiary)

            Text("Welcome to Devys")
                .font(.custom("JetBrains Mono", size: 16))
                .foregroundStyle(theme.text)

            Text("the artificial intelligence development environment")
                .font(.custom("JetBrains Mono", size: 12))
                .foregroundStyle(theme.textSecondary)
        }
    }

    // MARK: - Image Loading

    private func loadImage(size: CGSize) {
        // Skip if size is too small
        guard size.width > 100 && size.height > 100 else { return }

        // Skip if we already rendered for this image at similar size
        if hasAttemptedLoad && renderedImage != nil {
            let widthDiff = abs(size.width - lastLoadedSize.width)
            let heightDiff = abs(size.height - lastLoadedSize.height)
            if widthDiff < 50 && heightDiff < 50 {
                return
            }
        }

        hasAttemptedLoad = true
        lastLoadedSize = size

        // Get image to display - only get next image if we don't have one yet
        let imageToLoad: AnyWelcomeImage
        if let provided = image {
            imageToLoad = provided
        } else if let existing = currentImage {
            // Reuse existing image for resizes
            imageToLoad = existing
        } else if let next = WelcomeImageManager.shared.nextImage() {
            imageToLoad = next
        } else {
            // No images available
            isLoading = false
            loadError = WelcomeImageError.imageNotFound("No images available")
            return
        }

        currentImage = imageToLoad
        isLoading = true
        loadError = nil

        // Capture values for async task
        let accentColor = NSColor(theme.accent)
        let baseColor = NSColor(theme.base)
        let invert = imageToLoad.invertForDarkMode
        let columns = imageToLoad.optimalColumns

        Task.detached(priority: .userInitiated) {
            do {
                // Load source image
                let sourceImage = try await imageToLoad.loadImage()

                // Render ASCII art
                let rendered = try await ASCIIRenderPipeline.shared.render(
                    image: sourceImage,
                    size: size,
                    foregroundColor: accentColor,
                    backgroundColor: baseColor,
                    invert: invert,
                    contrast: 1.3,
                    columns: columns
                )

                await MainActor.run {
                    self.renderedImage = rendered
                    self.isLoading = false
                }
            } catch {
                // Try CPU fallback before updating UI
                var fallbackImage: NSImage?
                if let sourceImage = try? await imageToLoad.loadImage() {
                    fallbackImage = ASCIIRenderPipeline.shared.renderCPU(
                        image: sourceImage,
                        columns: columns,
                        foregroundColor: accentColor,
                        backgroundColor: baseColor,
                        invert: invert
                    )
                }

                await MainActor.run {
                    self.loadError = error
                    self.isLoading = false
                    self.renderedImage = fallbackImage
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
// periphery:ignore - SwiftUI preview entry point
struct ASCIIArtWelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        ASCIIArtWelcomeView()
            .frame(width: 800, height: 600)
    }
}
#endif

// swiftlint:enable function_body_length

#endif // os(macOS)
