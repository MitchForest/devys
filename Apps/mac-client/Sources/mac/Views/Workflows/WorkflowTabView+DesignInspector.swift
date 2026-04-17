import AppFeatures
import SwiftUI
import UI

extension WorkflowTabView {
    func designInspector(for definition: WorkflowDefinition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.space4) {
                detailsSection(for: definition)
                selectionSection(for: definition)
                workerSection(for: definition)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.space4)
        }
        .background(theme.base)
    }

    private func detailsSection(for definition: WorkflowDefinition) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            sectionHeader("Workflow")

            WorkflowFormField("Name") {
                TextInput(
                    "Workflow name",
                    text: workflowBinding(value: definition.name) {
                        onUpdateDefinition(.name($0))
                    }
                )
            }

            WorkflowFormField("Plan File") {
                TextInput(
                    "relative/or/absolute/path/to/plan.md",
                    text: workflowBinding(value: definition.planFilePath) {
                        onUpdateDefinition(.planFilePath($0))
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func selectionSection(for definition: WorkflowDefinition) -> some View {
        if let selectedNode = selectedWorkflowNode(in: definition) {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                sectionHeader("Selected Node")
                selectedNodeEditor(selectedNode, definition: definition)
            }
        } else if let selectedEdge = selectedWorkflowEdge(in: definition) {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                sectionHeader("Selected Edge")
                selectedEdgeEditor(selectedEdge, definition: definition)
            }
        }
    }

    private func workerSection(for definition: WorkflowDefinition) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            HStack {
                sectionHeader("Workers")
                Spacer()
                ActionButton("Add", icon: "plus", style: .ghost, action: onCreateWorker)
            }

            ForEach(definition.workers) { worker in
                WorkflowWorkerCardView(
                    worker: worker,
                    canDelete: definition.workers.count > 1,
                    onUpdateWorker: onUpdateWorker,
                    onDeleteWorker: onDeleteWorker
                )
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Typography.heading)
            .foregroundStyle(theme.text)
    }

    @ViewBuilder
    private func selectedNodeEditor(
        _ selectedNode: WorkflowNode,
        definition: WorkflowDefinition
    ) -> some View {
        selectedNodeTitleField(selectedNode, definition: definition)
        selectedNodeTypeField(selectedNode, definition: definition)

        if selectedNode.kind == .agent {
            selectedNodeWorkerField(selectedNode, definition: definition)
            selectedNodePromptField(selectedNode, definition: definition)
        }

        ActionButton("Set Entry Node", icon: "flag.fill", style: .ghost) {
            onUpdateDefinition(.entryNodeID(selectedNode.id))
        }
    }

    private func selectedNodeTitleField(
        _ selectedNode: WorkflowNode,
        definition: WorkflowDefinition
    ) -> some View {
        WorkflowFormField("Title") {
            TextInput(
                "Node title",
                text: Binding(
                    get: { selectedNode.title },
                    set: { newTitle in
                        replaceNode(selectedNode.id, in: definition) { $0.title = newTitle }
                    }
                )
            )
        }
    }

    private func selectedNodeTypeField(
        _ selectedNode: WorkflowNode,
        definition: WorkflowDefinition
    ) -> some View {
        WorkflowFormField("Type") {
            Picker(
                "Type",
                selection: Binding(
                    get: { selectedNode.kind },
                    set: { newKind in
                        applyNodeKind(newKind, selectedNode: selectedNode, definition: definition)
                    }
                )
            ) {
                ForEach(WorkflowNodeKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func applyNodeKind(
        _ newKind: WorkflowNodeKind,
        selectedNode: WorkflowNode,
        definition: WorkflowDefinition
    ) {
        replaceNode(selectedNode.id, in: definition) { node in
            node.kind = newKind
            if newKind == .finish {
                node.workerID = nil
                node.promptFilePath = nil
                node.promptOverride = nil
            } else if node.workerID == nil {
                node.workerID = definition.workers.first?.id
            }
        }
    }

    private func selectedNodeWorkerField(
        _ selectedNode: WorkflowNode,
        definition: WorkflowDefinition
    ) -> some View {
        WorkflowFormField("Worker") {
            Picker(
                "Worker",
                selection: Binding(
                    get: { selectedNode.workerID ?? definition.workers.first?.id ?? "" },
                    set: { workerID in
                        replaceNode(selectedNode.id, in: definition) { $0.workerID = workerID }
                    }
                )
            ) {
                ForEach(definition.workers) { worker in
                    Text(worker.resolvedDisplayName).tag(worker.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func selectedNodePromptField(
        _ selectedNode: WorkflowNode,
        definition: WorkflowDefinition
    ) -> some View {
        WorkflowFormField("Prompt Override") {
            TextEditorField(
                text: Binding(
                    get: { selectedNode.promptOverride ?? "" },
                    set: { promptOverride in
                        replaceNode(selectedNode.id, in: definition) {
                            $0.promptOverride = promptOverride
                        }
                    }
                ),
                minHeight: 140,
                isMonospaced: true
            )
        }
    }

    @ViewBuilder
    private func selectedEdgeEditor(
        _ selectedEdge: WorkflowEdge,
        definition: WorkflowDefinition
    ) -> some View {
        WorkflowFormField("Label") {
            TextInput(
                "Optional edge label",
                text: Binding(
                    get: { selectedEdge.label ?? "" },
                    set: { newLabel in
                        replaceEdge(selectedEdge.id, in: definition) { edge in
                            edge.label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                )
            )
        }

        Text(edgeSummary(selectedEdge, definition: definition))
            .font(Typography.caption)
            .foregroundStyle(theme.textSecondary)
    }
}
