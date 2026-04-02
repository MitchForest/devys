import SwiftUI
import UI

struct IOSClientCommandProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let store: IOSClientConnectionStore
    @Binding var draft: IOSClientConnectionStore.CommandProfileDraft

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DevysSpacing.space2) {
                    editorTitle
                    editorFields
                    editorCapabilities
                    editorFeedback
                    editorActions
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(DevysSpacing.space4)
            }
            .background(theme.base)
            .navigationTitle("Profile Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension IOSClientCommandProfileEditorSheet {
    var editorTitle: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space1) {
            Text(draft.isEditingExisting ? "Edit Command Profile" : "New Command Profile")
                .font(DevysTypography.heading)
                .foregroundStyle(theme.text)

            Text("Use one argument per line and one env var per line as KEY=VALUE.")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)
        }
    }

    var editorFields: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            TextField("id (example: ci_shell)", text: $draft.id)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)
                .disabled(draft.isEditingExisting && draft.isDefault)

            TextField("label", text: $draft.label)
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)

            TextField("command (empty means shell)", text: $draft.command)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .font(DevysTypography.sm)

            Text("Arguments (one per line)")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            TextEditor(text: $draft.argumentsText)
                .font(DevysTypography.xs)
                .frame(minHeight: 84)
                .padding(DevysSpacing.space1)
                .background(theme.content)
                .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))

            Text("Environment (KEY=VALUE per line)")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            TextEditor(text: $draft.environmentText)
                .font(DevysTypography.xs)
                .frame(minHeight: 120)
                .padding(DevysSpacing.space1)
                .background(theme.content)
                .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
        }
        .terminalCardStyle(theme: theme)
    }

    var editorCapabilities: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            Toggle("Require tmux", isOn: $draft.requiresTmux)
                .font(DevysTypography.xs)
                .tint(theme.accent)
            Toggle("Require claude", isOn: $draft.requiresClaude)
                .font(DevysTypography.xs)
                .tint(theme.accent)
            Toggle("Require codex", isOn: $draft.requiresCodex)
                .font(DevysTypography.xs)
                .tint(theme.accent)
            Toggle("Set as startup default after save", isOn: $draft.setAsStartupDefault)
                .font(DevysTypography.xs)
                .tint(theme.accent)
        }
        .terminalCardStyle(theme: theme)
    }

    @ViewBuilder
    var editorFeedback: some View {
        if let message = store.commandProfileEditorMessage {
            Text(message)
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)
        }

        ForEach(store.commandProfileValidationErrors, id: \.self) { message in
            Text(message)
                .font(DevysTypography.xs)
                .foregroundStyle(DevysColors.error)
        }

        ForEach(store.commandProfileValidationWarnings, id: \.self) { message in
            Text(message)
                .font(DevysTypography.xs)
                .foregroundStyle(DevysColors.warning)
        }
    }

    var editorActions: some View {
        HStack(spacing: DevysSpacing.space2) {
            actionButton("[validate]", tint: theme.textSecondary) {
                store.validateCommandProfileDraft(draft)
            }
            .disabled(!store.hasConnection || store.isMutatingCommandProfile)

            actionButton("[save]", tint: theme.accent) {
                store.saveCommandProfileDraft(draft) { success in
                    if success {
                        dismiss()
                    }
                }
            }
            .disabled(!store.hasConnection || store.isMutatingCommandProfile)
        }
    }

    func actionButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DevysTypography.sm)
                .foregroundStyle(tint)
                .padding(.horizontal, DevysSpacing.space2)
                .padding(.vertical, DevysSpacing.space1)
                .background(theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
        }
        .buttonStyle(.plain)
    }
}
