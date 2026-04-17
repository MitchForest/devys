import AppFeatures
import SwiftUI
import UI

@MainActor
struct WorkflowWorkerCardView: View {
    @Environment(\.devysTheme) private var theme

    let worker: WorkflowWorker
    let canDelete: Bool
    let onUpdateWorker: (String, WindowFeature.WorkflowWorkerUpdate) -> Void
    let onDeleteWorker: (String) -> Void

    @State private var isExpanded = false
    @State private var isAdvancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            header

            if isExpanded {
                basicFields
                promptField
                advancedSection
            }
        }
        .padding(Spacing.space3)
        .background(theme.card)
        .overlay {
            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                .stroke(theme.border, lineWidth: Spacing.borderWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: Spacing.space2) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(worker.resolvedDisplayName)
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(theme.text)
                Text(worker.kind.displayName)
                    .font(Typography.micro)
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
            if canDelete {
                ActionButton("", icon: "trash", style: .ghost, tone: .destructive) {
                    onDeleteWorker(worker.id)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        }
    }

    private var basicFields: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            WorkflowFormField("Display Name") {
                TextInput(
                    "Worker name",
                    text: workflowBinding(value: worker.displayName) {
                        onUpdateWorker(worker.id, .displayName($0))
                    }
                )
            }

            HStack(alignment: .top, spacing: Spacing.space3) {
                WorkflowFormField("Agent") {
                    Picker(
                        "Agent",
                        selection: workflowBinding(value: worker.kind) {
                            onUpdateWorker(worker.id, .kind($0))
                        }
                    ) {
                        ForEach(WorkflowAgentKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                WorkflowFormField("Execution") {
                    Picker(
                        "Execution",
                        selection: workflowBinding(value: worker.executionMode) {
                            onUpdateWorker(worker.id, .executionMode($0))
                        }
                    ) {
                        ForEach(WorkflowExecutionMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
    }

    private var promptField: some View {
        WorkflowPromptEditor(
            title: "Worker Prompt",
            text: workflowBinding(value: worker.prompt) {
                onUpdateWorker(worker.id, .prompt($0))
            }
        )
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isAdvancedExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.space2) {
                    Image(systemName: isAdvancedExpanded ? "chevron.down" : "chevron.right")
                        .font(Typography.caption)
                    Text("Advanced")
                        .font(Typography.caption.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(theme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAdvancedExpanded {
                advancedFields
                dangerousSection
            }
        }
    }

    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            HStack(alignment: .top, spacing: Spacing.space3) {
                WorkflowFormField("Model") {
                    TextInput(
                        "Optional model override",
                        text: workflowBinding(value: worker.launcher.model ?? "") {
                            onUpdateWorker(worker.id, .model($0))
                        }
                    )
                }

                WorkflowFormField("Reasoning") {
                    TextInput(
                        "low / medium / high / xhigh",
                        text: workflowBinding(value: worker.launcher.reasoningLevel ?? "") {
                            onUpdateWorker(worker.id, .reasoningLevel($0))
                        }
                    )
                }
            }

            WorkflowFormField("Extra Arguments") {
                TextInput(
                    "--flag value",
                    text: workflowBinding(value: worker.launcher.extraArguments.joined(separator: " ")) {
                        onUpdateWorker(worker.id, .extraArguments($0))
                    }
                )
            }
        }
    }

    private var dangerousSection: some View {
        HStack(alignment: .top, spacing: Spacing.space2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.warning)
                .font(Typography.caption)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: Spacing.space1) {
                Toggle(
                    "Allow dangerous permissions / bypass approvals",
                    isOn: workflowBinding(value: worker.launcher.dangerousPermissions) {
                        onUpdateWorker(worker.id, .dangerousPermissions($0))
                    }
                )
                .toggleStyle(.switch)

                Text("The agent will skip approval prompts for dangerous actions. Use only with trusted workflows.")
                    .font(Typography.micro)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(Spacing.space3)
        .background(theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                .stroke(theme.warning.opacity(0.35), lineWidth: Spacing.borderWidth)
        )
    }
}
