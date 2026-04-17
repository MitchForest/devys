import AppFeatures
import Canvas
import Foundation

extension WorkflowTabView {
    func selectedWorkflowNode(in definition: WorkflowDefinition) -> WorkflowNode? {
        guard let canvasID = canvas.selectedNodeIds.first else { return nil }
        return definition.nodes.first { $0.canvasID == canvasID }
    }

    func selectedWorkflowEdge(in definition: WorkflowDefinition) -> WorkflowEdge? {
        guard let canvasID = canvas.selectedConnectorIds.first else { return nil }
        return definition.edges.first { $0.canvasID == canvasID }
    }

    func edgeSummary(
        _ edge: WorkflowEdge,
        definition: WorkflowDefinition
    ) -> String {
        let source = definition.node(id: edge.sourceNodeID)?.displayTitle ?? edge.sourceNodeID
        let target = definition.node(id: edge.targetNodeID)?.displayTitle ?? edge.targetNodeID
        return "\(source) -> \(target)"
    }

    func replaceNode(
        _ nodeID: String,
        in definition: WorkflowDefinition,
        update: (inout WorkflowNode) -> Void
    ) {
        var nodes = definition.nodes
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        update(&nodes[index])
        onReplaceGraph(nodes, definition.edges)
    }

    func replaceEdge(
        _ edgeID: String,
        in definition: WorkflowDefinition,
        update: (inout WorkflowEdge) -> Void
    ) {
        var edges = definition.edges
        guard let index = edges.firstIndex(where: { $0.id == edgeID }) else { return }
        update(&edges[index])
        onReplaceGraph(definition.nodes, edges)
    }

    func applyDefinitionToCanvas(_ definition: WorkflowDefinition) {
        let canvasNodes = definition.nodes.enumerated().map { index, node in
            CanvasNode(
                id: node.canvasID,
                frame: CGRect(
                    x: node.frame.x,
                    y: node.frame.y,
                    width: node.frame.width,
                    height: node.frame.height
                ),
                zIndex: index,
                title: node.displayTitle
            )
        }

        let nodeIDsByWorkflowID = Dictionary(
            uniqueKeysWithValues: definition.nodes.map { ($0.id, $0.canvasID) }
        )
        let connectors = definition.edges.compactMap { edge -> WorkflowConnector? in
            guard let sourceID = nodeIDsByWorkflowID[edge.sourceNodeID],
                  let targetID = nodeIDsByWorkflowID[edge.targetNodeID] else {
                return nil
            }
            return WorkflowConnector(
                id: edge.canvasID,
                sourceId: sourceID,
                targetId: targetID,
                label: edge.label
            )
        }

        let signature = workflowCanvasSignature(nodes: canvasNodes, connectors: connectors)
        guard signature != lastCanvasSignature else { return }
        lastCanvasSignature = signature
        canvas.replaceContents(nodes: canvasNodes, connectors: connectors)
    }

    func syncCanvasGraph(_ definition: WorkflowDefinition) {
        let translated = translatedWorkflowGraph(
            definition: definition,
            canvasNodes: canvas.nodes,
            connectors: canvas.connectors
        )
        let signature = workflowGraphSignature(nodes: translated.nodes, edges: translated.edges)
        guard signature != workflowGraphSignature(
            nodes: definition.nodes,
            edges: definition.edges
        ) else {
            lastCanvasSignature = workflowCanvasSignature(nodes: canvas.nodes, connectors: canvas.connectors)
            return
        }

        lastCanvasSignature = workflowCanvasSignature(nodes: canvas.nodes, connectors: canvas.connectors)
        onReplaceGraph(translated.nodes, translated.edges)
    }

    func translatedWorkflowGraph(
        definition: WorkflowDefinition,
        canvasNodes: [CanvasNode],
        connectors: [WorkflowConnector]
    ) -> (nodes: [WorkflowNode], edges: [WorkflowEdge]) {
        let existingNodesByCanvasID = Dictionary(
            uniqueKeysWithValues: definition.nodes.map { ($0.canvasID, $0) }
        )
        let fallbackWorkerID = definition.workers.first?.id

        let nodes = canvasNodes.map { canvasNode in
            var node = existingNodesByCanvasID[canvasNode.id]
                ?? WorkflowNode.agent(
                    id: "node-\(canvasNode.id.uuidString.lowercased())",
                    title: canvasNode.title,
                    workerID: fallbackWorkerID ?? "",
                    frame: .defaultAgent
                )
            node.canvasID = canvasNode.id
            node.title = canvasNode.title
            node.frame = WorkflowNodeFrame(
                x: canvasNode.frame.origin.x,
                y: canvasNode.frame.origin.y,
                width: canvasNode.frame.width,
                height: canvasNode.frame.height
            )
            if node.kind == .agent, node.workerID == nil {
                node.workerID = fallbackWorkerID
            }
            return node
        }

        let workflowNodeIDsByCanvasID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.canvasID, $0.id) })
        let existingEdgesByCanvasID = Dictionary(
            uniqueKeysWithValues: definition.edges.map { ($0.canvasID, $0) }
        )

        let edges = connectors.compactMap { connector -> WorkflowEdge? in
            guard let sourceNodeID = workflowNodeIDsByCanvasID[connector.sourceId],
                  let targetNodeID = workflowNodeIDsByCanvasID[connector.targetId] else {
                return nil
            }

            var edge = existingEdgesByCanvasID[connector.id] ?? WorkflowEdge(
                id: "edge-\(connector.id.uuidString.lowercased())",
                canvasID: connector.id,
                sourceNodeID: sourceNodeID,
                targetNodeID: targetNodeID,
                label: connector.label
            )
            edge.canvasID = connector.id
            edge.sourceNodeID = sourceNodeID
            edge.targetNodeID = targetNodeID
            edge.label = connector.label
            return edge
        }

        return (nodes, edges)
    }
}

func workflowCanvasSignature(
    nodes: [CanvasNode],
    connectors: [WorkflowConnector]
) -> String {
    let nodeSignature = nodes
        .map { node in
            [
                node.id.uuidString,
                "\(node.frame.origin.x)",
                "\(node.frame.origin.y)",
                "\(node.frame.width)",
                "\(node.frame.height)",
                node.title
            ]
            .joined(separator: "|")
        }
        .joined(separator: ";")
    let connectorSignature = connectors
        .map { connector in
            [
                connector.id.uuidString,
                connector.sourceId.uuidString,
                connector.targetId.uuidString,
                connector.label ?? ""
            ]
            .joined(separator: "|")
        }
        .joined(separator: ";")
    return "\(nodeSignature)#\(connectorSignature)"
}

func workflowGraphSignature(
    nodes: [WorkflowNode],
    edges: [WorkflowEdge]
) -> String {
    let nodeSignature = nodes
        .map { node in
            [
                node.id,
                node.canvasID.uuidString,
                node.title,
                node.kind.rawValue,
                node.workerID ?? "",
                "\(node.frame.x)",
                "\(node.frame.y)",
                "\(node.frame.width)",
                "\(node.frame.height)",
                node.promptOverride ?? ""
            ]
            .joined(separator: "|")
        }
        .joined(separator: ";")
    let edgeSignature = edges
        .map { edge in
            [
                edge.id,
                edge.canvasID.uuidString,
                edge.sourceNodeID,
                edge.targetNodeID,
                edge.label ?? ""
            ]
            .joined(separator: "|")
        }
        .joined(separator: ";")
    return "\(nodeSignature)#\(edgeSignature)"
}
