// SnapEngine.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreGraphics

/// Engine for calculating snap alignments between nodes.
///
/// Detects when a node being dragged should snap to align with other nodes.
/// Supports edge-to-edge, same-level, center, viewport edge, and equal spacing alignments.
public struct SnapEngine: Sendable {

    /// Threshold distance for snapping (in canvas coordinates)
    public let threshold: CGFloat

    public init(threshold: CGFloat = CanvasLayout.snapThreshold) {
        self.threshold = threshold
    }

    /// Calculate snap adjustments for a node being moved.
    public func calculateSnap(
        movingFrame: CGRect,
        otherFrames: [CGRect],
        viewportBounds: CGRect? = nil
    ) -> SnapResult {
        var delta = CGSize.zero
        var guides: [SnapGuide] = []

        applyFrameSnaps(
            movingFrame: movingFrame,
            otherFrames: otherFrames,
            delta: &delta,
            guides: &guides
        )

        if let bounds = viewportBounds {
            applyViewportSnaps(
                movingFrame: movingFrame,
                viewportBounds: bounds,
                delta: &delta,
                guides: &guides
            )
        }

        applyEqualSpacingSnaps(
            movingFrame: movingFrame,
            otherFrames: otherFrames,
            delta: &delta,
            guides: &guides
        )

        return SnapResult(
            delta: delta,
            guides: guides
        )
    }
}

private extension SnapEngine {
    struct SnapCandidate {
        let delta: CGFloat
        let position: CGFloat
        let type: SnapGuide.SnapType
    }

    func applyFrameSnaps(
        movingFrame: CGRect,
        otherFrames: [CGRect],
        delta: inout CGSize,
        guides: inout [SnapGuide]
    ) {
        for targetFrame in otherFrames {
            if let (dx, guide) = findHorizontalSnap(moving: movingFrame, target: targetFrame) {
                applySnap(
                    axis: .vertical,
                    delta: dx,
                    current: &delta.width,
                    guides: &guides,
                    guide: guide
                )
            }

            if let (dy, guide) = findVerticalSnap(moving: movingFrame, target: targetFrame) {
                applySnap(
                    axis: .horizontal,
                    delta: dy,
                    current: &delta.height,
                    guides: &guides,
                    guide: guide
                )
            }
        }
    }

    func applyViewportSnaps(
        movingFrame: CGRect,
        viewportBounds: CGRect,
        delta: inout CGSize,
        guides: inout [SnapGuide]
    ) {
        if let (dx, guide) = findViewportHorizontalSnap(moving: movingFrame, viewport: viewportBounds) {
            applySnap(
                axis: .vertical,
                delta: dx,
                current: &delta.width,
                guides: &guides,
                guide: guide
            ) { $0.axis == .vertical && $0.type == .viewportEdge }
        }

        if let (dy, guide) = findViewportVerticalSnap(moving: movingFrame, viewport: viewportBounds) {
            applySnap(
                axis: .horizontal,
                delta: dy,
                current: &delta.height,
                guides: &guides,
                guide: guide
            ) { $0.axis == .horizontal && $0.type == .viewportEdge }
        }
    }

    func applyEqualSpacingSnaps(
        movingFrame: CGRect,
        otherFrames: [CGRect],
        delta: inout CGSize,
        guides: inout [SnapGuide]
    ) {
        guard let (spacingDelta, spacingGuides) = findEqualSpacing(
            moving: movingFrame,
            otherFrames: otherFrames
        ) else { return }

        let hasBetterWidth = abs(spacingDelta.width) < abs(delta.width) || delta.width == 0
        if abs(spacingDelta.width) > 0 && hasBetterWidth {
            delta.width = spacingDelta.width
            guides.append(contentsOf: spacingGuides.filter { $0.axis == .vertical })
        }

        let hasBetterHeight = abs(spacingDelta.height) < abs(delta.height) || delta.height == 0
        if abs(spacingDelta.height) > 0 && hasBetterHeight {
            delta.height = spacingDelta.height
            guides.append(contentsOf: spacingGuides.filter { $0.axis == .horizontal })
        }
    }

    func applySnap(
        axis: SnapGuide.Axis,
        delta: CGFloat,
        current: inout CGFloat,
        guides: inout [SnapGuide],
        guide: SnapGuide,
        removeFilter: ((SnapGuide) -> Bool)? = nil
    ) {
        guard abs(delta) < abs(current) || current == 0 else { return }
        current = delta

        if let removeFilter {
            guides.removeAll(where: removeFilter)
        } else {
            guides.removeAll { $0.axis == axis }
        }
        guides.append(guide)
    }

    // MARK: - Horizontal Snaps (X axis)

    func findHorizontalSnap(
        moving: CGRect,
        target: CGRect
    ) -> (CGFloat, SnapGuide)? {
        let candidates = horizontalCandidates(moving: moving, target: target)
        let start = min(moving.minY, target.minY)
        let end = max(moving.maxY, target.maxY)
        return bestSnap(candidates: candidates, axis: .vertical, start: start, end: end)
    }

    func horizontalCandidates(moving: CGRect, target: CGRect) -> [SnapCandidate] {
        [
            SnapCandidate(delta: target.minX - moving.minX, position: target.minX, type: .sameLevel),
            SnapCandidate(delta: target.maxX - moving.maxX, position: target.maxX, type: .sameLevel),
            SnapCandidate(delta: target.maxX - moving.minX, position: target.maxX, type: .edgeToEdge),
            SnapCandidate(delta: target.minX - moving.maxX, position: target.minX, type: .edgeToEdge),
            SnapCandidate(delta: target.midX - moving.midX, position: target.midX, type: .center)
        ]
    }

    // MARK: - Vertical Snaps (Y axis)

    func findVerticalSnap(
        moving: CGRect,
        target: CGRect
    ) -> (CGFloat, SnapGuide)? {
        let candidates = verticalCandidates(moving: moving, target: target)
        let start = min(moving.minX, target.minX)
        let end = max(moving.maxX, target.maxX)
        return bestSnap(candidates: candidates, axis: .horizontal, start: start, end: end)
    }

    func verticalCandidates(moving: CGRect, target: CGRect) -> [SnapCandidate] {
        [
            SnapCandidate(delta: target.minY - moving.minY, position: target.minY, type: .sameLevel),
            SnapCandidate(delta: target.maxY - moving.maxY, position: target.maxY, type: .sameLevel),
            SnapCandidate(delta: target.maxY - moving.minY, position: target.maxY, type: .edgeToEdge),
            SnapCandidate(delta: target.minY - moving.maxY, position: target.minY, type: .edgeToEdge),
            SnapCandidate(delta: target.midY - moving.midY, position: target.midY, type: .center)
        ]
    }

    // MARK: - Viewport Edge Snapping

    func findViewportHorizontalSnap(moving: CGRect, viewport: CGRect) -> (CGFloat, SnapGuide)? {
        let candidates = viewportHorizontalCandidates(moving: moving, viewport: viewport)
        return bestSnap(
            candidates: candidates,
            axis: .vertical,
            start: moving.minY,
            end: moving.maxY
        )
    }

    func viewportHorizontalCandidates(moving: CGRect, viewport: CGRect) -> [SnapCandidate] {
        [
            SnapCandidate(delta: viewport.minX - moving.minX, position: viewport.minX, type: .viewportEdge),
            SnapCandidate(delta: viewport.maxX - moving.maxX, position: viewport.maxX, type: .viewportEdge),
            SnapCandidate(delta: viewport.midX - moving.midX, position: viewport.midX, type: .viewportEdge)
        ]
    }

    func findViewportVerticalSnap(moving: CGRect, viewport: CGRect) -> (CGFloat, SnapGuide)? {
        let candidates = viewportVerticalCandidates(moving: moving, viewport: viewport)
        return bestSnap(
            candidates: candidates,
            axis: .horizontal,
            start: moving.minX,
            end: moving.maxX
        )
    }

    func viewportVerticalCandidates(moving: CGRect, viewport: CGRect) -> [SnapCandidate] {
        [
            SnapCandidate(delta: viewport.minY - moving.minY, position: viewport.minY, type: .viewportEdge),
            SnapCandidate(delta: viewport.maxY - moving.maxY, position: viewport.maxY, type: .viewportEdge),
            SnapCandidate(delta: viewport.midY - moving.midY, position: viewport.midY, type: .viewportEdge)
        ]
    }

    func bestSnap(
        candidates: [SnapCandidate],
        axis: SnapGuide.Axis,
        start: CGFloat,
        end: CGFloat
    ) -> (CGFloat, SnapGuide)? {
        var bestSnap: (CGFloat, SnapGuide)?
        for candidate in candidates {
            guard abs(candidate.delta) <= threshold else { continue }
            if let current = bestSnap, abs(candidate.delta) >= abs(current.0) {
                continue
            }

            bestSnap = (
                candidate.delta,
                SnapGuide(
                    axis: axis,
                    position: candidate.position,
                    start: start,
                    end: end,
                    type: candidate.type
                )
            )
        }
        return bestSnap
    }

    // MARK: - Equal Spacing Detection

    func findEqualSpacing(
        moving: CGRect,
        otherFrames: [CGRect]
    ) -> (CGSize, [SnapGuide])? {
        guard otherFrames.count >= 2 else { return nil }

        let horizontal = horizontalEqualSpacing(moving: moving, otherFrames: otherFrames)
        let vertical = verticalEqualSpacing(moving: moving, otherFrames: otherFrames)
        let delta = CGSize(width: horizontal.delta, height: vertical.delta)
        let guides = horizontal.guides + vertical.guides

        if delta.width != 0 || delta.height != 0 {
            return (delta, guides)
        }
        return nil
    }

    func horizontalEqualSpacing(
        moving: CGRect,
        otherFrames: [CGRect]
    ) -> (delta: CGFloat, guides: [SnapGuide]) {
        var deltaX: CGFloat = 0
        var guides: [SnapGuide] = []

        for i in 0..<otherFrames.count {
            for j in (i + 1)..<otherFrames.count {
                let a = otherFrames[i]
                let b = otherFrames[j]

                let verticalOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
                guard verticalOverlap > 0 else { continue }

                let leftFrame = a.minX < b.minX ? a : b
                let rightFrame = a.minX < b.minX ? b : a

                guard moving.minX > leftFrame.maxX && moving.maxX < rightFrame.minX else { continue }

                let gapLeft = moving.minX - leftFrame.maxX
                let gapRight = rightFrame.minX - moving.maxX
                let totalGap = gapLeft + moving.width + gapRight
                let idealGap = (totalGap - moving.width) / 2
                let centeredX = leftFrame.maxX + idealGap
                let candidateDelta = centeredX - moving.minX

                if abs(candidateDelta) <= threshold {
                    deltaX = candidateDelta
                    let guideY = (moving.minY + moving.maxY) / 2
                    guides.append(
                        SnapGuide(
                            axis: .vertical,
                            position: leftFrame.maxX + idealGap / 2,
                            start: guideY - 10,
                            end: guideY + 10,
                            type: .equalSpacing
                        )
                    )
                    guides.append(
                        SnapGuide(
                            axis: .vertical,
                            position: moving.maxX + idealGap / 2 + candidateDelta,
                            start: guideY - 10,
                            end: guideY + 10,
                            type: .equalSpacing
                        )
                    )
                }
            }
        }

        return (deltaX, guides)
    }

    func verticalEqualSpacing(
        moving: CGRect,
        otherFrames: [CGRect]
    ) -> (delta: CGFloat, guides: [SnapGuide]) {
        var deltaY: CGFloat = 0
        var guides: [SnapGuide] = []

        for i in 0..<otherFrames.count {
            for j in (i + 1)..<otherFrames.count {
                let a = otherFrames[i]
                let b = otherFrames[j]

                let horizontalOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
                guard horizontalOverlap > 0 else { continue }

                let topFrame = a.minY < b.minY ? a : b
                let bottomFrame = a.minY < b.minY ? b : a

                guard moving.minY > topFrame.maxY && moving.maxY < bottomFrame.minY else { continue }

                let gapTop = moving.minY - topFrame.maxY
                let gapBottom = bottomFrame.minY - moving.maxY
                let totalGap = gapTop + moving.height + gapBottom
                let idealGap = (totalGap - moving.height) / 2
                let centeredY = topFrame.maxY + idealGap
                let candidateDelta = centeredY - moving.minY

                if abs(candidateDelta) <= threshold {
                    deltaY = candidateDelta
                    let guideX = (moving.minX + moving.maxX) / 2
                    guides.append(
                        SnapGuide(
                            axis: .horizontal,
                            position: topFrame.maxY + idealGap / 2,
                            start: guideX - 10,
                            end: guideX + 10,
                            type: .equalSpacing
                        )
                    )
                    guides.append(
                        SnapGuide(
                            axis: .horizontal,
                            position: moving.maxY + idealGap / 2 + candidateDelta,
                            start: guideX - 10,
                            end: guideX + 10,
                            type: .equalSpacing
                        )
                    )
                }
            }
        }

        return (deltaY, guides)
    }
}

// MARK: - Snap Result

/// Result of snap calculation
public struct SnapResult: Sendable {
    public let delta: CGSize
    public let guides: [SnapGuide]

    public var hasSnap: Bool {
        delta.width != 0 || delta.height != 0
    }
}

// MARK: - Snap Guide

/// Visual guide line to show snap alignment
public struct SnapGuide: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let axis: Axis
    public let position: CGFloat
    public let start: CGFloat
    public let end: CGFloat
    public let type: SnapType

    public enum Axis: Sendable {
        case horizontal
        case vertical
    }

    public enum SnapType: Sendable {
        case edgeToEdge
        case sameLevel
        case center
        case equalSpacing
        case viewportEdge
    }
}
