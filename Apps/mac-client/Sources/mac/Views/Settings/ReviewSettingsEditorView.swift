import SwiftUI
import UI
import Workspace

struct ReviewSettingsEditorView: View {
    @Environment(\.devysTheme) private var theme

    @Binding var review: ReviewSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("REVIEW")
                    .font(DevysTypography.label)
                    .foregroundStyle(theme.text)

                Text(reviewSummary)
                    .font(DevysTypography.caption)
                    .foregroundStyle(theme.textSecondary)
            }

            Toggle(isOn: $review.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("enable_review")
                        .font(DevysTypography.label)
                        .foregroundStyle(theme.text)
                    Text("Allow this repository to create and display review runs")
                        .font(DevysTypography.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $review.reviewOnCommit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("review_on_commit")
                            .font(DevysTypography.label)
                            .foregroundStyle(theme.text)
                        Text("Install a repo-scoped post-commit hook that notifies Devys after each local commit.")
                            .font(DevysTypography.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .toggleStyle(.switch)

                labeledField("audit_harness") {
                    harnessPicker(selection: $review.auditHarness)
                }

                labeledField("follow_up_harness") {
                    harnessPicker(selection: $review.followUpHarness)
                }

                labeledField("audit_model_override") {
                    TextInput("inherit from launcher", text: optionalBinding(\.auditModelOverride))
                }

                labeledField("follow_up_model_override") {
                    TextInput("inherit from launcher", text: optionalBinding(\.followUpModelOverride))
                }

                labeledField("audit_reasoning_override") {
                    TextInput("inherit from launcher", text: optionalBinding(\.auditReasoningOverride))
                }

                labeledField("follow_up_reasoning_override") {
                    TextInput("inherit from launcher", text: optionalBinding(\.followUpReasoningOverride))
                }

                labeledField("additional_review_instructions") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextEditor(text: instructionsBinding)
                            .font(DevysTypography.body)
                            .frame(minHeight: 96)
                            .padding(8)
                            .inputChrome(.overlay)

                        Text(instructionsSummary)
                            .font(DevysTypography.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
            .disabled(!review.isEnabled)
            .opacity(review.isEnabled ? 1 : 0.6)
        }
    }

    private var reviewSummary: String {
        "Manual review uses one `Review...` entry. " +
            "Unset overrides inherit from the selected launcher template."
    }

    private var instructionsSummary: String {
        "Appended after the Devys audit scaffold. " +
            "Leave empty to use the default review prompt."
    }

    private func labeledField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DevysTypography.label)
                .foregroundStyle(theme.text)
            content()
        }
    }

    private func harnessPicker(selection: Binding<BuiltInLauncherKind>) -> some View {
        Picker("", selection: selection) {
            ForEach(BuiltInLauncherKind.allCases, id: \.self) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<ReviewSettings, String?>) -> Binding<String> {
        Binding(
            get: { review[keyPath: keyPath] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                review[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private var instructionsBinding: Binding<String> {
        Binding(
            get: { review.additionalInstructions ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                review.additionalInstructions = trimmed.isEmpty ? nil : trimmed
            }
        )
    }
}

private extension BuiltInLauncherKind {
    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }
}
