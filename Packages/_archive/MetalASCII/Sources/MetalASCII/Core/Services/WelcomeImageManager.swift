// WelcomeImageManager.swift
// DevysUI - Manager for welcome images and cycling
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import AppKit
import SwiftUI

// MARK: - Welcome Image Manager

/// Manages bundled and user welcome images, handles cycling between images.
@MainActor
public final class WelcomeImageManager: ObservableObject {

    // MARK: - Singleton

    public static let shared = WelcomeImageManager()

    // MARK: - Published Properties

    @Published public private(set) var bundledArtwork: [BundledArtwork]
    @Published public private(set) var userImages: [UserWelcomeImage]
    @Published public private(set) var disabledBundledIds: Set<String>

    // MARK: - Private Properties

    private var cycleIndex: Int

    // MARK: - Initialization

    private init() {
        // Load bundled artwork
        self.bundledArtwork = BundledArtworkCatalog.all

        // Load user data from manifest
        let manifest = WelcomeImageStorage.loadManifest()
        self.userImages = manifest.images
        self.disabledBundledIds = manifest.disabledBundledIds
        self.cycleIndex = manifest.cycleIndex
    }

    // MARK: - All Enabled Images

    /// All enabled images (bundled + user) in display order
    public var allEnabledImages: [AnyWelcomeImage] {
        var images: [AnyWelcomeImage] = []

        // Add enabled bundled artwork
        for artwork in bundledArtwork where artwork.isEnabled && !disabledBundledIds.contains(artwork.id) {
            images.append(AnyWelcomeImage(artwork))
        }

        // Add enabled user images
        for image in userImages where image.isEnabled {
            images.append(AnyWelcomeImage(image))
        }

        return images
    }

    /// Total count of enabled images
    public var enabledCount: Int {
        allEnabledImages.count
    }

    // MARK: - Cycling

    /// Get the next image in the cycle
    public func nextImage() -> AnyWelcomeImage? {
        let enabled = allEnabledImages
        guard !enabled.isEmpty else { return nil }

        let image = enabled[cycleIndex % enabled.count]
        cycleIndex += 1

        // Persist cycle index
        persistCycleIndex()

        return image
    }

    /// Get a specific image by ID
    public func image(id: String) -> AnyWelcomeImage? {
        if let bundled = bundledArtwork.first(where: { $0.id == id }) {
            return AnyWelcomeImage(bundled)
        }
        if let user = userImages.first(where: { $0.id == id }) {
            return AnyWelcomeImage(user)
        }
        return nil
    }

    /// Get a random enabled image
    public func randomImage() -> AnyWelcomeImage? {
        allEnabledImages.randomElement()
    }

    /// Reset the cycle to the beginning
    public func resetCycle() {
        cycleIndex = 0
        persistCycleIndex()
    }

    // MARK: - Bundled Artwork Management

    /// Toggle whether a bundled artwork is enabled
    public func toggleBundledArtwork(id: String, enabled: Bool) {
        if enabled {
            disabledBundledIds.remove(id)
        } else {
            disabledBundledIds.insert(id)
        }
        persistManifest()
    }

    /// Check if bundled artwork is enabled
    public func isBundledArtworkEnabled(id: String) -> Bool {
        !disabledBundledIds.contains(id)
    }

    // MARK: - User Image Management

    /// Import a user image from a URL
    public func importImage(from url: URL) async throws -> UserWelcomeImage {
        let image = try WelcomeImageStorage.importImage(from: url)
        userImages.append(image)
        return image
    }

    /// Delete a user image
    public func deleteImage(_ image: UserWelcomeImage) throws {
        try WelcomeImageStorage.deleteImage(image)
        userImages.removeAll { $0.id == image.id }
    }

    /// Update a user image's settings
    public func updateImage(_ image: UserWelcomeImage) {
        if let index = userImages.firstIndex(where: { $0.id == image.id }) {
            userImages[index] = image
            persistManifest()
        }
    }

    /// Toggle whether a user image is enabled
    public func toggleUserImage(id: String, enabled: Bool) {
        if let index = userImages.firstIndex(where: { $0.id == id }) {
            userImages[index].isEnabled = enabled
            persistManifest()
        }
    }

    // MARK: - Persistence

    private func persistCycleIndex() {
        var manifest = WelcomeImageStorage.loadManifest()
        manifest.cycleIndex = cycleIndex
        try? WelcomeImageStorage.saveManifest(manifest)
    }

    private func persistManifest() {
        var manifest = WelcomeImageStorage.loadManifest()
        manifest.images = userImages
        manifest.disabledBundledIds = disabledBundledIds
        manifest.cycleIndex = cycleIndex
        try? WelcomeImageStorage.saveManifest(manifest)
    }

    // MARK: - Reload

    /// Reload images from storage
    public func reload() {
        bundledArtwork = BundledArtworkCatalog.all
        let manifest = WelcomeImageStorage.loadManifest()
        userImages = manifest.images
        disabledBundledIds = manifest.disabledBundledIds
        cycleIndex = manifest.cycleIndex
    }
}
