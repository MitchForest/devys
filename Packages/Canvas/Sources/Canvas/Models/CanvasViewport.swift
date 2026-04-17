// CanvasViewport.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreGraphics
import Observation
import SwiftUI

/// Observable model for canvas viewport state.
///
/// The viewport controls the "camera" view into the infinite canvas:
/// - `offset` - Pan position (where the camera is looking)
/// - `scale` - Zoom level (how close the camera is)
@MainActor
@Observable
public final class CanvasViewport {

    // MARK: - Properties

    /// Pan offset - the canvas position relative to viewport center.
    /// Positive X = canvas moved right, Positive Y = canvas moved down.
    public private(set) var offset: CGPoint = .zero

    /// Zoom scale factor. 1.0 = 100%, 0.5 = 50%, 2.0 = 200%.
    public private(set) var scale: CGFloat = CanvasLayout.defaultScale

    /// Callback for notifying parent when state changes
    @ObservationIgnored var onDirty: (() -> Void)?

    // MARK: - Initialization

    public init(offset: CGPoint = .zero, scale: CGFloat = CanvasLayout.defaultScale) {
        self.offset = offset
        self.scale = scale
    }

    // MARK: - Pan Operations

    /// Move the canvas by a delta (in screen points).
    /// Converts screen delta to canvas delta accounting for current scale.
    func pan(by screenDelta: CGSize) {
        offset.x += screenDelta.width / scale
        offset.y += screenDelta.height / scale
        markDirty()
    }

    /// Set absolute offset position.
    func setOffset(_ newOffset: CGPoint) {
        offset = newOffset
        markDirty()
    }

    // MARK: - Zoom Operations

    /// Zoom in by a fixed factor.
    func zoomIn() {
        let newScale = scale * 1.25
        scale = min(newScale, CanvasLayout.maxScale)
        markDirty()
    }

    /// Zoom out by a fixed factor.
    func zoomOut() {
        let newScale = scale / 1.25
        scale = max(newScale, CanvasLayout.minScale)
        markDirty()
    }

    /// Reset to default zoom and center position.
    func zoomToFit() {
        scale = CanvasLayout.defaultScale
        offset = .zero
        markDirty()
    }

    /// Reset to 100% zoom, keeping current position.
    func zoomTo100() {
        scale = 1.0
        markDirty()
    }

    /// Set zoom to a specific scale, clamped to valid range.
    func setScale(_ newScale: CGFloat) {
        scale = min(max(newScale, CanvasLayout.minScale), CanvasLayout.maxScale)
        markDirty()
    }

    // MARK: - Private

    private func markDirty() {
        onDirty?()
    }
}
