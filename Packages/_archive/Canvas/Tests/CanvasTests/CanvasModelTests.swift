// CanvasModelTests.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Testing
import CoreGraphics
@testable import Canvas

@Suite("CanvasModel Tests")
struct CanvasModelTests {

    @Test("Create node assigns unique ID and z-index")
    @MainActor
    func createNode() {
        let canvas = CanvasModel()
        let id1 = canvas.createNode(at: .zero, title: "A")
        let id2 = canvas.createNode(at: CGPoint(x: 100, y: 100), title: "B")

        #expect(id1 != id2)
        #expect(canvas.nodes.count == 2)

        let node1 = canvas.node(withId: id1)
        let node2 = canvas.node(withId: id2)
        #expect(node1 != nil)
        #expect(node2 != nil)
        #expect(node1!.zIndex < node2!.zIndex)
    }

    @Test("Delete node removes connectors")
    @MainActor
    func deleteNodeRemovesConnectors() {
        let canvas = CanvasModel()
        let a = canvas.createNode(at: .zero, title: "A")
        let b = canvas.createNode(at: CGPoint(x: 300, y: 0), title: "B")

        canvas.createConnector(from: a, sourcePort: .right, to: b, targetPort: .left)
        #expect(canvas.connectors.count == 1)

        canvas.deleteNode(a)
        #expect(canvas.connectors.isEmpty)
    }

    @Test("Selection management")
    @MainActor
    func selection() {
        let canvas = CanvasModel()
        let id = canvas.createNode(at: .zero)

        #expect(canvas.isNodeSelected(id))
        canvas.clearSelection()
        #expect(!canvas.isNodeSelected(id))

        canvas.selectNode(id)
        #expect(canvas.isNodeSelected(id))

        canvas.toggleNodeSelection(id)
        #expect(!canvas.isNodeSelected(id))
    }

    @Test("Connector creation prevents duplicates and self-connections")
    @MainActor
    func connectorValidation() {
        let canvas = CanvasModel()
        let a = canvas.createNode(at: .zero)
        let b = canvas.createNode(at: CGPoint(x: 300, y: 0))

        let c1 = canvas.createConnector(from: a, sourcePort: .right, to: b, targetPort: .left)
        #expect(c1 != nil)

        // Duplicate should fail
        let c2 = canvas.createConnector(from: a, sourcePort: .right, to: b, targetPort: .left)
        #expect(c2 == nil)
        #expect(canvas.connectors.count == 1)

        // Self-connection should fail
        let c3 = canvas.createConnector(from: a, sourcePort: .right, to: a, targetPort: .left)
        #expect(c3 == nil)
    }

    @Test("Coordinate transforms round-trip")
    @MainActor
    func coordinateRoundTrip() {
        let canvas = CanvasModel()
        let viewportSize = CGSize(width: 800, height: 600)

        let screenPoint = CGPoint(x: 400, y: 300)
        let canvasPoint = canvas.canvasPoint(from: screenPoint, viewportSize: viewportSize)
        let backToScreen = canvas.screenPoint(from: canvasPoint, viewportSize: viewportSize)

        #expect(abs(backToScreen.x - screenPoint.x) < 0.001)
        #expect(abs(backToScreen.y - screenPoint.y) < 0.001)
    }
}
