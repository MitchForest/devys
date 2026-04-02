// CharacterWeightGenerator.swift
// DevysUI - Pre-computes character weights for shape-aware ASCII art matching
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import Foundation

// MARK: - Character Weights

/// Represents the 5-directional weight distribution of an ASCII character.
///
/// Weights describe how the visual "mass" of a character is distributed:
/// - `top`: Brightness in upper region
/// - `bottom`: Brightness in lower region
/// - `left`: Brightness in left region
/// - `right`: Brightness in right region
/// - `middle`: Brightness in center region
public struct CharacterWeights: Codable, Sendable {
    public let character: String
    public let asciiCode: Int
    public let weights: [Float]  // [top, bottom, left, right, middle]
    public let totalDensity: Float

    public var top: Float { weights[0] }
    public var bottom: Float { weights[1] }
    public var left: Float { weights[2] }
    public var right: Float { weights[3] }
    public var middle: Float { weights[4] }

    public init(character: String, asciiCode: Int, weights: [Float], totalDensity: Float) {
        self.character = character
        self.asciiCode = asciiCode
        self.weights = weights
        self.totalDensity = totalDensity
    }
}

// MARK: - Weight Table

/// Pre-computed weight table for all printable ASCII characters.
public struct CharacterWeightTable: Codable, Sendable {
    public let characters: [CharacterWeights]
    public let fontName: String
    public let cellWidth: Int
    public let cellHeight: Int
    public let generatedAt: Date

    /// Flat array of weights for Metal buffer (95 chars × 5 weights)
    public var flatWeights: [Float] {
        characters.flatMap { $0.weights }
    }

    /// Array of ASCII codes for Metal buffer
    public var asciiCodes: [Int32] {
        characters.map { Int32($0.asciiCode) }
    }

    /// Characters sorted by total density (for optimization)
    public var sortedByDensity: [CharacterWeights] {
        characters.sorted { $0.totalDensity < $1.totalDensity }
    }
}

// MARK: - Character Weight Generator

/// Generates weight tables for ASCII characters by rendering them and analyzing
/// the distribution of visual weight across 5 regions.
public final class CharacterWeightGenerator: @unchecked Sendable {

    // MARK: - Properties

    private let font: NSFont
    private let cellWidth: Int
    private let cellHeight: Int

    // MARK: - Initialization

    /// Create a generator with specified font and cell dimensions.
    ///
    /// - Parameters:
    ///   - font: Font to use for rendering characters
    ///   - cellWidth: Width of each character cell in pixels
    ///   - cellHeight: Height of each character cell in pixels
    public init(font: NSFont? = nil, cellWidth: Int = 16, cellHeight: Int = 24) {
        self.font = font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
    }

    // MARK: - Generation

    /// Generate weight table for all 95 printable ASCII characters (32-126).
    public func generateWeightTable() -> CharacterWeightTable {
        var characters: [CharacterWeights] = []

        // Generate weights for ASCII 32 (space) through 126 (~)
        for code in 32...126 {
            guard let scalar = UnicodeScalar(code) else { continue }
            let char = Character(scalar)
            let weights = computeWeights(for: char)
            let totalDensity = weights.reduce(0, +) / Float(weights.count)

            characters.append(CharacterWeights(
                character: String(char),
                asciiCode: code,
                weights: weights,
                totalDensity: totalDensity
            ))
        }

        return CharacterWeightTable(
            characters: characters,
            fontName: font.fontName,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            generatedAt: Date()
        )
    }

    // MARK: - Weight Computation

    /// Compute 5-directional weights for a single character.
    ///
    /// - Parameter char: Character to analyze
    /// - Returns: Array of 5 floats: [top, bottom, left, right, middle]
    private func computeWeights(for char: Character) -> [Float] {
        // Render character to bitmap
        guard let bitmap = renderCharacter(char) else {
            return [0, 0, 0, 0, 0]
        }

        // Sample 9 regions (3x3 grid)
        let regions = sample9Regions(from: bitmap)

        // Convert to 5 directional weights
        return regionsToWeights(regions)
    }

    /// Render a character to a grayscale bitmap.
    private func renderCharacter(_ char: Character) -> CGContext? {
        let size = NSSize(width: cellWidth, height: cellHeight)

        // Create bitmap context
        guard let context = CGContext(
            data: nil,
            width: cellWidth,
            height: cellHeight,
            bitsPerComponent: 8,
            bytesPerRow: cellWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        // Clear to black (0)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

        // Set up for drawing white text
        context.setFillColor(gray: 1, alpha: 1)

        // Create attributed string
        let string = String(char)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: string, attributes: attributes)

        // Calculate centered position
        let stringSize = attrString.size()
        let x = (CGFloat(cellWidth) - stringSize.width) / 2
        let y = (CGFloat(cellHeight) - stringSize.height) / 2

        // Draw using NSGraphicsContext
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        attrString.draw(at: NSPoint(x: x, y: y))

        NSGraphicsContext.restoreGraphicsState()

        return context
    }

    /// Sample 9 regions from a bitmap, returning average brightness for each.
    ///
    /// Layout:
    /// ```
    /// [0][1][2]  (top row: TL, T, TR)
    /// [3][4][5]  (middle row: L, M, R)
    /// [6][7][8]  (bottom row: BL, B, BR)
    /// ```
    private func sample9Regions(from context: CGContext) -> [Float] {
        guard let data = context.data else {
            return Array(repeating: 0, count: 9)
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: cellWidth * cellHeight)

        // Calculate region boundaries
        let regionWidth = cellWidth / 3
        let regionHeight = cellHeight / 3

        var regions = [Float](repeating: 0, count: 9)

        for regionY in 0..<3 {
            for regionX in 0..<3 {
                let regionIndex = regionY * 3 + regionX

                let startX = regionX * regionWidth
                let startY = regionY * regionHeight
                let endX = min(startX + regionWidth, cellWidth)
                let endY = min(startY + regionHeight, cellHeight)

                var total: Float = 0
                var count = 0

                for y in startY..<endY {
                    for x in startX..<endX {
                        let pixelIndex = y * cellWidth + x
                        total += Float(pixels[pixelIndex]) / 255.0
                        count += 1
                    }
                }

                regions[regionIndex] = count > 0 ? total / Float(count) : 0
            }
        }

        return regions
    }

    /// Convert 9-region samples to 5 directional weights.
    ///
    /// - Parameter regions: Array of 9 regional brightness values
    /// - Returns: Array of 5 weights: [top, bottom, left, right, middle]
    private func regionsToWeights(_ regions: [Float]) -> [Float] {
        // Region layout:
        // [0][1][2]  TL  T  TR
        // [3][4][5]  L   M  R
        // [6][7][8]  BL  B  BR

        let tl = regions[0], t = regions[1], tr = regions[2]
        let l = regions[3], m = regions[4], r = regions[5]
        let bl = regions[6], b = regions[7], br = regions[8]

        let top = (tl + t + tr) / 3.0
        let bottom = (bl + b + br) / 3.0
        let left = (tl + l + bl) / 3.0
        let right = (tr + r + br) / 3.0
        let middle = m

        return [top, bottom, left, right, middle]
    }

    // MARK: - Persistence

    /// Save weight table to JSON file.
    public func save(_ table: CharacterWeightTable, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(table)
        try data.write(to: url)
    }

    /// Load weight table from JSON file.
    public static func load(from url: URL) throws -> CharacterWeightTable {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CharacterWeightTable.self, from: data)
    }

    /// Load bundled weight table from package resources.
    public static func loadBundled() -> CharacterWeightTable? {
        guard let url = Bundle.module.url(forResource: "character-weights", withExtension: "json") else {
            return nil
        }
        return try? load(from: url)
    }

    /// Generate and return a default weight table (used when bundled not available).
    public static func generateDefault() -> CharacterWeightTable {
        let generator = CharacterWeightGenerator()
        return generator.generateWeightTable()
    }
}

// MARK: - Shared Instance

public extension CharacterWeightGenerator {
    /// Shared weight table, loaded from bundle or generated on demand.
    static let sharedWeightTable: CharacterWeightTable = {
        if let bundled = loadBundled() {
            return bundled
        }
        // Generate at runtime if not bundled
        return generateDefault()
    }()
}

#endif // os(macOS)
