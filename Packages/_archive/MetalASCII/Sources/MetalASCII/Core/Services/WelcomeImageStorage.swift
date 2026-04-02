// WelcomeImageStorage.swift
// DevysUI - Storage utilities for user welcome images
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import AppKit

// MARK: - Welcome Image Storage

/// Handles file storage for user-uploaded welcome images.
public enum WelcomeImageStorage {

    /// Directory for user welcome images
    public static var userImagesDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let devysDir = appSupport.appendingPathComponent("Devys", isDirectory: true)
        let imagesDir = devysDir.appendingPathComponent("WelcomeImages", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        return imagesDir
    }

    /// Path to user images manifest
    public static var manifestURL: URL {
        userImagesDirectory.appendingPathComponent("manifest.json")
    }

    // MARK: - Manifest Operations

    /// Load user images manifest
    public static func loadManifest() -> UserImagesManifest {
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(UserImagesManifest.self, from: data) else {
            return UserImagesManifest()
        }
        return manifest
    }

    /// Save user images manifest
    public static func saveManifest(_ manifest: UserImagesManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL)
    }

    // MARK: - Image Operations

    /// Import an image from a URL
    public static func importImage(from sourceURL: URL) throws -> UserWelcomeImage {
        let originalFilename = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension.lowercased()

        // Validate format
        guard ["jpg", "jpeg", "png", "heic", "webp"].contains(ext) else {
            throw WelcomeImageError.invalidFormat
        }

        // Generate unique filename
        let id = UUID().uuidString
        let filename = "\(id).\(ext)"
        let destinationURL = userImagesDirectory.appendingPathComponent(filename)

        // Load and optionally resize image
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw WelcomeImageError.failedToLoad(originalFilename)
        }

        // Resize if too large (max 2000px on longest edge)
        let resizedImage = resizeIfNeeded(image, maxDimension: 2000)

        // Save to destination
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw WelcomeImageError.failedToSave(filename)
        }

        let imageData: Data?
        if ext == "png" {
            imageData = bitmap.representation(using: .png, properties: [:])
        } else {
            imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        }

        guard let data = imageData else {
            throw WelcomeImageError.failedToSave(filename)
        }

        try data.write(to: destinationURL)

        // Create record
        let userImage = UserWelcomeImage(
            id: id,
            filename: filename,
            originalFilename: originalFilename
        )

        // Update manifest
        var manifest = loadManifest()
        manifest.images.append(userImage)
        try saveManifest(manifest)

        return userImage
    }

    /// Delete a user image
    public static func deleteImage(_ image: UserWelcomeImage) throws {
        // Delete file
        let fileURL = userImagesDirectory.appendingPathComponent(image.filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        // Update manifest
        var manifest = loadManifest()
        manifest.images.removeAll { $0.id == image.id }
        try saveManifest(manifest)
    }

    /// Resize image if larger than max dimension
    private static func resizeIfNeeded(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let maxSide = max(size.width, size.height)

        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: newSize),
                   from: CGRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()

        return newImage
    }
}

// MARK: - User Images Manifest

/// Manifest file for user-uploaded images.
public struct UserImagesManifest: Codable {
    public var version: Int = 1
    public var images: [UserWelcomeImage] = []
    public var disabledBundledIds: Set<String> = []
    public var cycleIndex: Int = 0

    public init() {}
}
