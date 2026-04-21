import AppFeatures
import SwiftUI
import UI

@MainActor
struct WorkflowSidebarSectionView: View {
    @Environment(\.devysTheme) private var theme
    private let deleteRunMessage =
        "This removes the saved run history, attempts, and artifacts for this run. "
        + "It does not delete the workflow definition or plan file."
    private let deleteDefinitionMessage =
        "This removes the workflow definition. Existing runs for this workflow are kept; "
        + "delete them separately if you want them gone."

    let definitions: [WorkflowDefinition]
    let runs: [WorkflowRun]
    let onOpenDefinition: (String) -> Void
    let onStartDefinition: (String) -> Void
    let onDeleteDefinition: (String) -> Void
    let onOpenRun: (UUID) -> Void
    let onDeleteRun: (UUID) -> Void

    @State private var hoveredRunID: UUID?
    @State private var hoveredDefinitionID: String?
    @State private var pendingDeleteRunID: UUID?
    @State private var pendingDeleteDefinitionID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            if definitions.isEmpty, runs.isEmpty {
                Text("No workflows configured for this workspace.")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, Spacing.space3)
                    .padding(.vertical, 4)
            } else {
                if !definitions.isEmpty {
                    groupTitle("Definitions")
                    ForEach(definitions) { definition in
                        definitionRow(definition)
                    }
                }

                if !runs.isEmpty {
                    groupTitle("Runs")
                    ForEach(runs) { run in
                        runRow(run)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.space3)
        .padding(.bottom, Spacing.space3)
        .alert("Delete Run?", isPresented: deleteRunConfirmationBinding) {
            Button("Delete Run", role: .destructive) {
                guard let pendingDeleteRunID else { return }
                onDeleteRun(pendingDeleteRunID)
                self.pendingDeleteRunID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteRunID = nil
            }
        } message: {
            Text(deleteRunMessage)
        }
        .alert("Delete Workflow?", isPresented: deleteDefinitionConfirmationBinding) {
            Button("Delete Workflow", role: .destructive) {
                guard let pendingDeleteDefinitionID else { return }
                onDeleteDefinition(pendingDeleteDefinitionID)
                self.pendingDeleteDefinitionID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteDefinitionID = nil
            }
        } message: {
            Text(deleteDefinitionMessage)
        }
    }

    private func groupTitle(
        _ title: String
    ) -> some View {
        Text(title)
            .font(Typography.micro.weight(.semibold))
            .foregroundStyle(theme.textTertiary)
            .padding(.top, Spacing.space1)
    }

    private func definitionRow(
        _ definition: WorkflowDefinition
    ) -> some View {
        let showsTrash = hoveredDefinitionID == definition.id
        return HStack(spacing: Spacing.space2) {
            Button {
                onOpenDefinition(definition.id)
            } label: {
                definitionRowLabel(definition)
            }
            .buttonStyle(.plain)

            definitionRowAccessory(definition, showsTrash: showsTrash)
        }
        .padding(.horizontal, Spacing.space2)
        .padding(.vertical, Spacing.space2)
        .background(theme.card)
        .overlay {
            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                .stroke(theme.border, lineWidth: Spacing.borderWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .onHover { isHovering in
            if isHovering {
                hoveredDefinitionID = definition.id
            } else if hoveredDefinitionID == definition.id {
                hoveredDefinitionID = nil
            }
        }
        .contextMenu {
            Button("Open Workflow") { onOpenDefinition(definition.id) }
            Button("Run Workflow") { onStartDefinition(definition.id) }
            Divider()
            Button("Delete Workflow…", role: .destructive) {
                pendingDeleteDefinitionID = definition.id
            }
        }
    }

    private func definitionRowLabel(_ definition: WorkflowDefinition) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(definition.name.isEmpty ? "Untitled Workflow" : definition.name)
                .font(Typography.body)
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Text(definition.planFilePath.isEmpty ? "No plan file" : definition.planFilePath)
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func definitionRowAccessory(
        _ definition: WorkflowDefinition,
        showsTrash: Bool
    ) -> some View {
        ZStack {
            ActionButton("", icon: "play.fill", style: .ghost) {
                onStartDefinition(definition.id)
            }
            .opacity(showsTrash ? 0 : 1)
            .allowsHitTesting(!showsTrash)
            ActionButton("", icon: "trash", style: .ghost, tone: .destructive) {
                pendingDeleteDefinitionID = definition.id
            }
            .opacity(showsTrash ? 1 : 0)
            .allowsHitTesting(showsTrash)
        }
        .frame(width: 28, height: 28)
    }

    private func runRow(
        _ run: WorkflowRun
    ) -> some View {
        let showsDeleteAction = hoveredRunID == run.id

        return HStack(spacing: Spacing.space2) {
            Button {
                onOpenRun(run.id)
            } label: {
                runRowLabel(run, showsDeleteAction: showsDeleteAction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.space2)
        .padding(.vertical, Spacing.space2)
        .background(theme.card)
        .overlay {
            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                .stroke(theme.border, lineWidth: Spacing.borderWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .onHover { isHovering in
            if isHovering {
                hoveredRunID = run.id
            } else if hoveredRunID == run.id {
                hoveredRunID = nil
            }
        }
        .contextMenu {
            Button("Open Run") {
                onOpenRun(run.id)
            }
            Divider()
            Button("Delete Run…", role: .destructive) {
                pendingDeleteRunID = run.id
            }
        }
    }

    private func runRowLabel(
        _ run: WorkflowRun,
        showsDeleteAction: Bool
    ) -> some View {
        HStack(spacing: Spacing.space2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    run.currentPhaseTitle
                        ?? run.currentNodeID
                        ?? "Workflow Run"
                )
                .font(Typography.body)
                .foregroundStyle(theme.text)
                .lineLimit(1)

                Text(run.displayStatus)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            runTrailingAccessory(run, showsDeleteAction: showsDeleteAction)
        }
    }

    @ViewBuilder
    private func runTrailingAccessory(
        _ run: WorkflowRun,
        showsDeleteAction: Bool
    ) -> some View {
        ZStack {
            Circle()
                .fill(run.status.isActive ? theme.accent : theme.textTertiary)
                .frame(width: 8, height: 8)
                .opacity(showsDeleteAction ? 0 : 1)

            ActionButton("", icon: "trash", style: .ghost, tone: .destructive) {
                pendingDeleteRunID = run.id
            }
            .opacity(showsDeleteAction ? 1 : 0)
            .allowsHitTesting(showsDeleteAction)
            .accessibilityHidden(!showsDeleteAction)
        }
        .frame(width: 28, height: 28)
    }

    private var deleteRunConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteRunID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteRunID = nil
                }
            }
        )
    }

    private var deleteDefinitionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteDefinitionID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteDefinitionID = nil
                }
            }
        )
    }
}
