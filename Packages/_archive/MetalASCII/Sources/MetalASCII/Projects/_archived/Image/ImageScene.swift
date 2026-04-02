// ImageScene.swift
// MetalASCII - Image-to-ASCII scene using the existing render pipeline
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import Metal
import MetalKit
import simd

// MARK: - Image Scene

/// ASCII art scene that converts images to ASCII with animation effects.
///
/// Features:
/// - Uses the proven ASCIIRenderPipeline for high-quality conversion
/// - Cycles through bundled famous artwork
/// - Subtle animation effects (color pulse, scanlines)
/// - Full dithering support
public final class ImageScene: ASCIIScene, @unchecked Sendable {

    public let name = "Image"
    public let description = "Famous artwork rendered as ASCII art"

    // MARK: - Configuration

    /// Current image index in the artwork catalog
    public var currentImageIndex: Int = 0 {
        didSet {
            if currentImageIndex != oldValue {
                loadCurrentImage()
            }
        }
    }

    /// Whether to auto-cycle through images
    public var autoCycle: Bool = false

    /// Time between auto-cycles (seconds)
    public var cycleInterval: Float = 10.0

    /// Animation intensity (0-1)
    public var animationIntensity: Float = 0.3

    /// Number of ASCII columns
    public var columns: Int = 100

    /// Dithering mode
    public var ditherMode: UInt32 = 2

    /// Invert brightness for light images
    public var invertBrightness: Bool = false

    // MARK: - State

    private var time: Float = 0
    private var cycleTimer: Float = 0
    private var viewportSize: CGSize = .zero
    private var sourceImage: NSImage?
    private var isLoading: Bool = false

    // MARK: - Output

    public private(set) var asciiOutput: [[Character]] = []
    public private(set) var brightnessOutput: [[Float]] = []

    // MARK: - Metal

    private let device: MTLDevice

    // MARK: - Initialization

    public required init(device: MTLDevice) throws {
        self.device = device

        // Start with a default size
        resize(to: CGSize(width: 1200, height: 800))

        // Load the first image
        loadCurrentImage()
    }

    // MARK: - Image Loading

    private func loadCurrentImage() {
        let artwork = BundledArtworkCatalog.all
        guard !artwork.isEmpty else { return }

        let index = currentImageIndex % artwork.count
        let selected = artwork[index]

        // Update invert setting based on image
        invertBrightness = selected.invertForDarkMode

        isLoading = true

        // Load bundled image synchronously (they're local files, fast to load)
        if let image = loadBundledImageSync(selected) {
            sourceImage = image
            isLoading = false
            regenerateASCII()
        } else {
            metalASCIILog("Failed to load image: \(selected.filename)")
            isLoading = false
        }
    }

    /// Load a bundled artwork image synchronously.
    private func loadBundledImageSync(_ artwork: BundledArtwork) -> NSImage? {
        let filename = artwork.filename

        // Extract name and extension
        let name: String
        let ext: String
        if let dotIndex = filename.lastIndex(of: ".") {
            name = String(filename[..<dotIndex])
            ext = String(filename[filename.index(after: dotIndex)...])
        } else {
            name = filename
            ext = "jpg"
        }

        // Try multiple paths for bundle resources
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Artwork"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        if let url = Bundle.module.url(forResource: name, withExtension: ext),
           let image = NSImage(contentsOf: url) {
            return image
        }

        if let resourcePath = Bundle.module.resourcePath {
            let directPath = (resourcePath as NSString).appendingPathComponent("Artwork/\(filename)")
            if let image = NSImage(contentsOfFile: directPath) {
                return image
            }

            let flatPath = (resourcePath as NSString).appendingPathComponent(filename)
            if let image = NSImage(contentsOfFile: flatPath) {
                return image
            }
        }

        return nil
    }

    /// Get the current artwork info
    public var currentArtwork: BundledArtwork? {
        let artwork = BundledArtworkCatalog.all
        guard !artwork.isEmpty else { return nil }
        return artwork[currentImageIndex % artwork.count]
    }

    /// Move to next image
    public func nextImage() {
        let count = BundledArtworkCatalog.all.count
        currentImageIndex = (currentImageIndex + 1) % count
    }

    /// Move to previous image
    public func previousImage() {
        let count = BundledArtworkCatalog.all.count
        currentImageIndex = (currentImageIndex - 1 + count) % count
    }

    // MARK: - ASCIIScene Protocol

    public func resize(to size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        viewportSize = size

        // Regenerate if we have an image
        if sourceImage != nil {
            regenerateASCII()
        }
    }

    public func update(deltaTime: Float) {
        time += deltaTime

        // Handle auto-cycling
        if autoCycle {
            cycleTimer += deltaTime
            if cycleTimer >= cycleInterval {
                cycleTimer = 0
                nextImage()
            }
        }

        // Apply subtle animation effects to brightness
        if animationIntensity > 0 {
            applyAnimationEffects()
        }
    }

    public func render(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor) {
        // This scene generates ASCII on CPU via the existing pipeline
        // Just clear the render pass
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.endEncoding()
        }
    }

    // MARK: - ASCII Generation

    private func regenerateASCII() {
        guard let image = sourceImage else { return }
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return }

        // Use the shape-aware generator for best results
        let generator = ShapeAwareASCIIGenerator()
        generator.invertBrightness = invertBrightness
        generator.contrastBoost = 1.3
        generator.gamma = 0.9

        // Calculate optimal columns based on viewport
        let effectiveColumns = min(columns, Int(viewportSize.width / 8))

        // Generate ASCII text
        let text = generator.convert(image: image, columns: effectiveColumns)

        // Parse into character and brightness arrays
        parseASCIIText(text)
    }

    private func parseASCIIText(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        asciiOutput = []
        brightnessOutput = []

        let ramp = ASCIICharacterRamp.standard
        let rampCount = ramp.count

        for line in lines {
            var charRow: [Character] = []
            var brightRow: [Float] = []

            for char in line {
                charRow.append(char)

                // Estimate brightness from character position in ramp
                if let index = ramp.firstIndex(of: char) {
                    let brightness = Float(ramp.distance(from: ramp.startIndex, to: index)) / Float(rampCount - 1)
                    brightRow.append(brightness)
                } else {
                    brightRow.append(0)
                }
            }

            asciiOutput.append(charRow)
            brightnessOutput.append(brightRow)
        }
    }

    // MARK: - Animation Effects

    private func applyAnimationEffects() {
        guard !brightnessOutput.isEmpty else { return }

        let rows = brightnessOutput.count
        guard rows > 0 else { return }

        // Subtle pulse effect
        let pulse = sin(time * 2.0) * 0.05 * animationIntensity

        // Scanline effect
        let scanlineY = Int(time * 30) % rows

        for row in 0..<rows {
            for col in 0..<brightnessOutput[row].count {
                var brightness = brightnessOutput[row][col]

                // Apply pulse
                brightness += pulse

                // Apply scanline highlight
                if row == scanlineY {
                    brightness += 0.1 * animationIntensity
                }

                // Subtle wave distortion
                let wave = sin(Float(col) * 0.1 + time * 3.0) * 0.02 * animationIntensity
                brightness += wave

                brightnessOutput[row][col] = max(0, min(1, brightness))
            }
        }
    }

    /// Get the current frame as an ASCII string
    public func getASCIIString() -> String {
        return asciiOutput.map { String($0) }.joined(separator: "\n")
    }
}

#endif // os(macOS)
