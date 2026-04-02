// CanvasModel+Coordinates.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Coordinate Transforms

public extension CanvasModel {

    /// Convert a screen point to canvas coordinates.
    func canvasPoint(from screenPoint: CGPoint, viewportSize: CGSize) -> CGPoint {
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        return CGPoint(
            x: (screenPoint.x - center.x) / scale - offset.x,
            y: (screenPoint.y - center.y) / scale - offset.y
        )
    }

    /// Convert a canvas point to screen coordinates.
    func screenPoint(from canvasPoint: CGPoint, viewportSize: CGSize) -> CGPoint {
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        return CGPoint(
            x: (canvasPoint.x + offset.x) * scale + center.x,
            y: (canvasPoint.y + offset.y) * scale + center.y
        )
    }

    /// Get the visible rectangle in canvas coordinates.
    func visibleRect(viewportSize: CGSize) -> CGRect {
        let topLeft = canvasPoint(from: .zero, viewportSize: viewportSize)
        let bottomRight = canvasPoint(
            from: CGPoint(x: viewportSize.width, y: viewportSize.height),
            viewportSize: viewportSize
        )
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    /// Convert a size from canvas to screen coordinates.
    func screenSize(from canvasSize: CGSize) -> CGSize {
        CGSize(
            width: canvasSize.width * scale,
            height: canvasSize.height * scale
        )
    }

    /// Return the topmost node id under a screen point, if any.
    func nodeId(at screenPoint: CGPoint, viewportSize: CGSize) -> UUID? {
        let canvasPoint = canvasPoint(from: screenPoint, viewportSize: viewportSize)
        for node in nodesSortedByZIndex.reversed() where node.frame.contains(canvasPoint) {
            return node.id
        }
        return nil
    }
}

// MARK: - Zoom Toward Point

public extension CanvasModel {

    /// Zoom toward a specific screen point (e.g., cursor position).
    func zoom(to newScale: CGFloat, toward screenPoint: CGPoint, viewportSize: CGSize) {
        let clampedScale = min(max(newScale, CanvasLayout.minScale), CanvasLayout.maxScale)

        // Get the canvas point under the cursor before zoom
        let canvasPointBeforeZoom = canvasPoint(from: screenPoint, viewportSize: viewportSize)

        // Apply new scale
        setScale(clampedScale)

        // Get where that canvas point would be on screen after zoom
        let screenPointAfterZoom = self.screenPoint(from: canvasPointBeforeZoom, viewportSize: viewportSize)

        // Adjust offset to keep the point stationary
        let deltaScreen = CGSize(
            width: screenPoint.x - screenPointAfterZoom.x,
            height: screenPoint.y - screenPointAfterZoom.y
        )
        pan(by: deltaScreen)
    }
}
