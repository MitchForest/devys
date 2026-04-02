// ASCIIFilter.swift
// DevysUI - Programmatic ASCII art conversion
//
// Converts images to ASCII art using pure Swift implementation
// for maximum compatibility and reliability.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import SwiftUI
import CoreImage

// swiftlint:disable function_body_length

// MARK: - ASCII Art Generator

/// Converts images to ASCII art using programmatic brightness mapping.
///
/// ## Overview
/// This generator samples image pixels and maps brightness values to
/// ASCII characters, creating a text-based representation of images.
///
/// ## Usage
/// ```swift
/// let generator = ASCIIArtGenerator()
/// let asciiText = generator.convert(image: myImage, columns: 80)
/// ```
public final class ASCIIArtGenerator: @unchecked Sendable {

    // MARK: - Character Ramp

    /// ASCII characters ordered by visual density (dark to light)
    private let characterRamp = " .`'-:;=+*xoO#%@MW"

    /// Extended character ramp for more gradation
    private let extendedRamp = " .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$"

    // MARK: - Properties

    /// Whether to use the extended character ramp
    public var useExtendedRamp: Bool = false

    /// Whether to invert the brightness mapping
    public var invertBrightness: Bool = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Converts an image to ASCII art text.
    ///
    /// - Parameters:
    ///   - image: Source image to convert
    ///   - columns: Number of character columns (width)
    ///   - aspectRatio: Character aspect ratio (default 0.5 for typical monospace)
    /// - Returns: Multi-line string containing ASCII art
    public func convert(image: NSImage, columns: Int = 80, aspectRatio: Double = 0.5) -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        let width = cgImage.width
        let height = cgImage.height

        // Calculate sampling dimensions
        let cellWidth = max(1, width / columns)
        let rows = Int(Double(height) / Double(cellWidth) * aspectRatio)
        let cellHeight = max(1, height / rows)

        // Create bitmap context for pixel access
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return ""
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return ""
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let ramp = useExtendedRamp ? extendedRamp : characterRamp
        let rampCount = ramp.count

        var result = ""

        for row in 0..<rows {
            for col in 0..<columns {
                let x = col * cellWidth
                let y = row * cellHeight

                // Sample brightness at this cell
                var totalBrightness: Double = 0
                var sampleCount = 0

                for dy in 0..<min(cellHeight, height - y) {
                    for dx in 0..<min(cellWidth, width - x) {
                        let pixelIndex = ((y + dy) * width + (x + dx)) * 4
                        let r = Double(pixels[pixelIndex])
                        let g = Double(pixels[pixelIndex + 1])
                        let b = Double(pixels[pixelIndex + 2])

                        // Luminance formula
                        let brightness = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                        totalBrightness += brightness
                        sampleCount += 1
                    }
                }

                var avgBrightness = sampleCount > 0 ? totalBrightness / Double(sampleCount) : 0

                if invertBrightness {
                    avgBrightness = 1.0 - avgBrightness
                }

                // Map brightness to character
                let charIndex = min(rampCount - 1, Int(avgBrightness * Double(rampCount)))
                let char = ramp[ramp.index(ramp.startIndex, offsetBy: charIndex)]
                result.append(char)
            }
            result.append("\n")
        }

        return result
    }

    /// Converts an image to an NSImage containing rendered ASCII art.
    ///
    /// - Parameters:
    ///   - image: Source image to convert
    ///   - columns: Number of character columns
    ///   - foregroundColor: Color for ASCII characters
    ///   - backgroundColor: Background color
    ///   - fontSize: Font size for rendering
    /// - Returns: NSImage containing the rendered ASCII art
    public func renderToImage(
        image: NSImage,
        columns: Int = 60,
        foregroundColor: NSColor = .white,
        backgroundColor: NSColor = .clear,
        fontSize: CGFloat = 8
    ) -> NSImage? {
        let asciiText = convert(image: image, columns: columns)

        guard !asciiText.isEmpty else { return nil }

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor
        ]

        let attributedString = NSAttributedString(string: asciiText, attributes: attributes)
        let size = attributedString.size()

        let resultImage = NSImage(size: size, flipped: false) { rect in
            if backgroundColor != .clear {
                backgroundColor.setFill()
                rect.fill()
            }
            attributedString.draw(at: .zero)
            return true
        }

        return resultImage
    }
}

// MARK: - NSImage Extension

public extension NSImage {
    /// Converts this image to ASCII art text.
    ///
    /// - Parameters:
    ///   - columns: Number of character columns
    ///   - inverted: Whether to invert brightness
    /// - Returns: ASCII art as a multi-line string
    func toASCIIText(columns: Int = 80, inverted: Bool = false) -> String {
        let generator = ASCIIArtGenerator()
        generator.invertBrightness = inverted
        return generator.convert(image: self, columns: columns)
    }

    /// Converts this image to an ASCII art rendered image.
    ///
    /// - Parameters:
    ///   - foregroundColor: Color for ASCII characters
    ///   - columns: Number of character columns
    ///   - inverted: Whether to invert brightness
    /// - Returns: NSImage containing rendered ASCII art
    func toASCII(foregroundColor: Color = .white, columns: Int = 60, inverted: Bool = false) -> NSImage? {
        let generator = ASCIIArtGenerator()
        generator.invertBrightness = inverted
        return generator.renderToImage(
            image: self,
            columns: columns,
            foregroundColor: NSColor(foregroundColor)
        )
    }
}

// swiftlint:enable function_body_length
