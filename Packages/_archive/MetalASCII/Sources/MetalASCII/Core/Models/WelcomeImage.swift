// WelcomeImage.swift
// DevysUI - Welcome image models for ASCII art display
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import AppKit

// MARK: - Welcome Image Protocol

/// Protocol for images that can be displayed as ASCII art in welcome tabs.
public protocol WelcomeImage: Identifiable, Sendable {
    var id: String { get }
    var title: String { get }
    var artist: String? { get }
    var year: Int? { get }
    var isEnabled: Bool { get }
    var optimalColumns: Int { get }
    var invertForDarkMode: Bool { get }

    /// Load the image data
    func loadImage() async throws -> NSImage
}

// MARK: - Bundled Artwork

/// Represents artwork bundled with the app.
public struct BundledArtwork: WelcomeImage, Codable, Hashable {
    public let id: String
    public let title: String
    public let artist: String?
    public let year: Int?
    public let filename: String
    public let aspectRatio: CGFloat
    public let optimalColumns: Int
    public let invertForDarkMode: Bool
    public var isEnabled: Bool

    public init(
        id: String,
        title: String,
        artist: String? = nil,
        year: Int? = nil,
        filename: String,
        aspectRatio: CGFloat = 1.5,
        optimalColumns: Int = 120,
        invertForDarkMode: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.year = year
        self.filename = filename
        self.aspectRatio = aspectRatio
        self.optimalColumns = optimalColumns
        self.invertForDarkMode = invertForDarkMode
        self.isEnabled = isEnabled
    }

    public func loadImage() async throws -> NSImage {
        // Extract name and extension from filename
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
        // Path 1: With Artwork subdirectory (for .copy resources)
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Artwork") {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        // Path 2: Direct in bundle (for .process resources)
        if let url = Bundle.module.url(forResource: name, withExtension: ext) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        // Path 3: Look in bundle's resource path directly
        if let resourcePath = Bundle.module.resourcePath {
            let directPath = (resourcePath as NSString).appendingPathComponent("Artwork/\(filename)")
            if FileManager.default.fileExists(atPath: directPath),
               let image = NSImage(contentsOfFile: directPath) {
                return image
            }

            // Also try without subdirectory
            let flatPath = (resourcePath as NSString).appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: flatPath),
               let image = NSImage(contentsOfFile: flatPath) {
                return image
            }
        }

        throw WelcomeImageError.imageNotFound(filename)
    }

    /// Display string with artist and year
    public var attribution: String {
        var parts: [String] = []
        if let artist = artist {
            parts.append(artist)
        }
        if let year = year {
            parts.append("(\(year))")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - User Welcome Image

/// Represents a user-uploaded image for welcome tabs.
public struct UserWelcomeImage: WelcomeImage, Codable, Hashable {
    public let id: String
    public let filename: String
    public let originalFilename: String
    public let addedDate: Date
    public var displayName: String?
    public var isEnabled: Bool
    public var optimalColumns: Int
    public var invertForDarkMode: Bool

    public var title: String {
        displayName ?? originalFilename
    }

    public var artist: String? { nil }
    public var year: Int? { nil }

    public init(
        id: String = UUID().uuidString,
        filename: String,
        originalFilename: String,
        addedDate: Date = Date(),
        displayName: String? = nil,
        isEnabled: Bool = true,
        optimalColumns: Int = 100,
        invertForDarkMode: Bool = false
    ) {
        self.id = id
        self.filename = filename
        self.originalFilename = originalFilename
        self.addedDate = addedDate
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.optimalColumns = optimalColumns
        self.invertForDarkMode = invertForDarkMode
    }

    /// URL to the stored image file
    public var fileURL: URL {
        WelcomeImageStorage.userImagesDirectory.appendingPathComponent(filename)
    }

    public func loadImage() async throws -> NSImage {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw WelcomeImageError.imageNotFound(filename)
        }
        guard let image = NSImage(contentsOf: fileURL) else {
            throw WelcomeImageError.failedToLoad(filename)
        }
        return image
    }
}

// MARK: - Errors

/// Errors related to welcome image operations.
public enum WelcomeImageError: Error, LocalizedError {
    case imageNotFound(String)
    case failedToLoad(String)
    case failedToSave(String)
    case invalidFormat
    case storageFull

    public var errorDescription: String? {
        switch self {
        case .imageNotFound(let name):
            return "Image not found: \(name)"
        case .failedToLoad(let name):
            return "Failed to load image: \(name)"
        case .failedToSave(let name):
            return "Failed to save image: \(name)"
        case .invalidFormat:
            return "Invalid image format. Supported: JPEG, PNG, HEIC, WebP"
        case .storageFull:
            return "Storage is full. Remove some images to add new ones."
        }
    }
}

// MARK: - Any Welcome Image Wrapper

/// Type-erased wrapper for WelcomeImage to use in collections.
public struct AnyWelcomeImage: WelcomeImage, Hashable {
    public let id: String
    public let title: String
    public let artist: String?
    public let year: Int?
    public let isEnabled: Bool
    public let optimalColumns: Int
    public let invertForDarkMode: Bool

    private let _loadImage: @Sendable () async throws -> NSImage
    private let _hashValue: Int

    public init<T: WelcomeImage>(_ image: T) where T: Hashable {
        self.id = image.id
        self.title = image.title
        self.artist = image.artist
        self.year = image.year
        self.isEnabled = image.isEnabled
        self.optimalColumns = image.optimalColumns
        self.invertForDarkMode = image.invertForDarkMode
        self._loadImage = image.loadImage
        self._hashValue = image.hashValue
    }

    public func loadImage() async throws -> NSImage {
        try await _loadImage()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(_hashValue)
    }

    public static func == (lhs: AnyWelcomeImage, rhs: AnyWelcomeImage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Bundled Artwork Catalog

/// Static catalog of bundled artwork.
public enum BundledArtworkCatalog {

    /// All bundled artwork
    public static let all: [BundledArtwork] = [
        BundledArtwork(
            id: "great-wave",
            title: "The Great Wave off Kanagawa",
            artist: "Katsushika Hokusai",
            year: 1831,
            filename: "great-wave.jpg",
            aspectRatio: 1.5,
            optimalColumns: 120,
            invertForDarkMode: false
        ),
        BundledArtwork(
            id: "starry-night",
            title: "The Starry Night",
            artist: "Vincent van Gogh",
            year: 1889,
            filename: "starry-night.jpg",
            aspectRatio: 1.26,
            optimalColumns: 120,
            invertForDarkMode: false
        ),
        BundledArtwork(
            id: "mona-lisa",
            title: "Mona Lisa",
            artist: "Leonardo da Vinci",
            year: 1503,
            filename: "mona-lisa.jpg",
            aspectRatio: 0.69,
            optimalColumns: 80,
            invertForDarkMode: false
        ),
        BundledArtwork(
            id: "persistence-memory",
            title: "The Persistence of Memory",
            artist: "Salvador Dalí",
            year: 1931,
            filename: "persistence-memory.jpg",
            aspectRatio: 1.33,
            optimalColumns: 120,
            invertForDarkMode: false
        ),
        BundledArtwork(
            id: "girl-pearl-earring",
            title: "Girl with a Pearl Earring",
            artist: "Johannes Vermeer",
            year: 1665,
            filename: "girl-pearl-earring.jpg",
            aspectRatio: 0.86,
            optimalColumns: 80,
            invertForDarkMode: false
        ),
        BundledArtwork(
            id: "the-scream",
            title: "The Scream",
            artist: "Edvard Munch",
            year: 1893,
            filename: "the-scream.jpg",
            aspectRatio: 0.8,
            optimalColumns: 80,
            invertForDarkMode: false
        ),
        BundledArtwork(
            id: "creation-adam",
            title: "The Creation of Adam",
            artist: "Michelangelo",
            year: 1512,
            filename: "creation-adam.jpg",
            aspectRatio: 2.3,
            optimalColumns: 150,
            invertForDarkMode: false
        ),
        BundledArtwork(
            id: "wanderer-fog",
            title: "Wanderer Above the Sea of Fog",
            artist: "Caspar David Friedrich",
            year: 1818,
            filename: "wanderer-fog.jpg",
            aspectRatio: 0.75,
            optimalColumns: 80,
            invertForDarkMode: false
        ),
        BundledArtwork(
            id: "vitruvian-man",
            title: "Vitruvian Man",
            artist: "Leonardo da Vinci",
            year: 1490,
            filename: "vitruvian-man.jpg",
            aspectRatio: 1.0,
            optimalColumns: 100,
            invertForDarkMode: true
        ),
        BundledArtwork(
            id: "birth-venus",
            title: "The Birth of Venus",
            artist: "Sandro Botticelli",
            year: 1485,
            filename: "birth-venus.jpg",
            aspectRatio: 1.57,
            optimalColumns: 140,
            invertForDarkMode: false
        )
    ]

    /// Get artwork by ID
    public static func artwork(id: String) -> BundledArtwork? {
        all.first { $0.id == id }
    }
}
