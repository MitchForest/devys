// CanvasModel+NodeDrag.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreGraphics
import AppKit

public extension CanvasModel {

    /// Begin dragging a node. Returns the start frame.
    func beginNodeDrag(_ nodeId: UUID) -> CGRect? {
        guard let node = node(withId: nodeId) else { return nil }
        if !isNodeSelected(nodeId) {
            selectNode(nodeId)
        }
        return node.frame
    }

    /// Update a node drag. Returns the screen-space offset to apply.
    func updateNodeDrag(
        nodeId: UUID,
        startFrame: CGRect,
        translation: CGSize,
        shiftHeld: Bool
    ) -> CGSize {
        guard let node = node(withId: nodeId) else { return .zero }

        let canvasDelta = CGSize(
            width: translation.width / scale,
            height: translation.height / scale
        )

        setNodeDragOffset(nodeId, offset: canvasDelta)

        let proposedFrame = CGRect(
            x: startFrame.origin.x + canvasDelta.width,
            y: startFrame.origin.y + canvasDelta.height,
            width: startFrame.width,
            height: startFrame.height
        )

        setSnappingDisabled(shiftHeld)

        let snappedFrame: CGRect
        if shiftHeld {
            snappedFrame = proposedFrame
            clearSnapGuides()
        } else {
            snappedFrame = calculateSnapForNode(nodeId, proposedFrame: proposedFrame)
        }

        let offset = CGSize(
            width: snappedFrame.origin.x - node.frame.origin.x,
            height: snappedFrame.origin.y - node.frame.origin.y
        )

        return CGSize(
            width: offset.width * scale,
            height: offset.height * scale
        )
    }

    /// End a node drag. Commits the final position.
    func endNodeDrag(
        nodeId: UUID,
        startFrame: CGRect,
        translation: CGSize
    ) {
        let canvasDelta = CGSize(
            width: translation.width / scale,
            height: translation.height / scale
        )

        let proposedFrame = CGRect(
            x: startFrame.origin.x + canvasDelta.width,
            y: startFrame.origin.y + canvasDelta.height,
            width: startFrame.width,
            height: startFrame.height
        )

        let snappedFrame = calculateSnapForNode(nodeId, proposedFrame: proposedFrame)

        moveNodeTo(nodeId, position: snappedFrame.origin)
        resetDragState(nodeId: nodeId)
    }

    /// Reset all drag state for a node.
    func resetDragState(nodeId: UUID) {
        clearSnapGuides()
        setSnappingDisabled(false)
        clearNodeDragOffset(nodeId)
    }
}
