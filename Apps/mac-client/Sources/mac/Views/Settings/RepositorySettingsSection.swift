// RepositorySettingsSection.swift
// Devys - Repository-scoped launcher and startup profile settings.

import SwiftUI
import Workspace
import UI

struct RepositorySettingsSection: View {
    @Environment(\.devysTheme) private var theme
    @Environment(RepositorySettingsStore.self) private var repositorySettingsStore

    let repositoryRootURL: URL
    let repositoryDisplayName: String?

    private var settings: RepositorySettings {
        repositorySettingsStore.settings(for: repositoryRootURL)
    }

    var body: some View {
        SettingsSection(title: "REPOSITORY") {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(repositoryDisplayName ?? repositoryRootURL.lastPathComponent)
                        .font(DevysTypography.label)
                        .foregroundStyle(theme.text)

                    Text(repositoryRootURL.path)
                        .font(DevysTypography.caption)
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                }

                Separator()

                WorkspaceCreationDefaultsEditorView(
                    defaults: Binding(
                        get: { settings.workspaceCreation },
                        set: { newValue in
                            updateSettings { $0.workspaceCreation = newValue }
                        }
                    )
                )

                Separator()

                LauncherTemplateEditorView(
                    title: "Claude",
                    template: launcherBinding(\.claudeLauncher)
                )

                Separator()

                LauncherTemplateEditorView(
                    title: "Codex",
                    template: launcherBinding(\.codexLauncher)
                )

                Separator()

                StartupProfilesEditorView(
                    profiles: Binding(
                        get: { settings.startupProfiles },
                        set: { newProfiles in
                            updateSettings { updated in
                                updated.startupProfiles = newProfiles
                                if let defaultStartupProfileID = updated.defaultStartupProfileID,
                                   newProfiles.contains(where: { $0.id == defaultStartupProfileID }) == false {
                                    updated.defaultStartupProfileID = nil
                                }
                            }
                        }
                    ),
                    defaultProfileID: Binding(
                        get: { settings.defaultStartupProfileID },
                        set: { newValue in
                            updateSettings { $0.defaultStartupProfileID = newValue }
                        }
                    )
                )

                Separator()

                RepositoryPortLabelsEditorView(
                    labels: Binding(
                        get: { settings.portLabels },
                        set: { newValue in
                            updateSettings { $0.portLabels = newValue }
                        }
                    )
                )
            }
        }
    }

    private func launcherBinding(
        _ keyPath: WritableKeyPath<RepositorySettings, LauncherTemplate>
    ) -> Binding<LauncherTemplate> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                updateSettings { updated in
                    updated[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func updateSettings(_ mutation: (inout RepositorySettings) -> Void) {
        var updated = settings
        mutation(&updated)
        repositorySettingsStore.updateSettings(updated, for: repositoryRootURL)
    }
}

private struct WorkspaceCreationDefaultsEditorView: View {
    @Environment(\.devysTheme) private var theme

    @Binding var defaults: WorkspaceCreationDefaults

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WORKSPACE CREATION DEFAULTS")
                .font(DevysTypography.label)
                .foregroundStyle(theme.text)

            VStack(alignment: .leading, spacing: 10) {
                labeledField("default_base_branch") {
                    TextInput("main", text: $defaults.defaultBaseBranch)
                }

                Toggle(isOn: $defaults.copyIgnoredFiles) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("copy_ignored_files")
                            .font(DevysTypography.label)
                            .foregroundStyle(theme.text)
                        Text("Include ignored files when creating a new workspace copy")
                            .font(DevysTypography.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $defaults.copyUntrackedFiles) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("copy_untracked_files")
                            .font(DevysTypography.label)
                            .foregroundStyle(theme.text)
                        Text("Include untracked files when creating a new workspace copy")
                            .font(DevysTypography.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
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
}

private struct LauncherTemplateEditorView: View {
    @Environment(\.devysTheme) private var theme

    let title: String
    @Binding var template: LauncherTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(DevysTypography.label)
                .foregroundStyle(theme.text)

            VStack(alignment: .leading, spacing: 10) {
                labeledField("base_command") {
                    TextInput("claude", text: $template.executable)
                }

                labeledField("model_override") {
                    TextInput("optional", text: optionalBinding(\.model))
                }

                labeledField("reasoning_level") {
                    TextInput("optional", text: optionalBinding(\.reasoningLevel))
                }

                Toggle(isOn: $template.dangerousPermissions) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("dangerous_permissions")
                            .font(DevysTypography.label)
                            .foregroundStyle(theme.text)
                        Text("Use the CLI's no-approval / bypass-permissions mode when available")
                            .font(DevysTypography.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .toggleStyle(.switch)

                labeledField("launch_behavior") {
                    Picker("launch_behavior", selection: $template.executionBehavior) {
                        ForEach(LauncherExecutionBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                labeledField("extra_arguments") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextEditor(text: argumentsBinding)
                            .font(DevysTypography.body)
                            .frame(minHeight: 72)
                            .padding(8)
                            .inputChrome(.overlay)

                        Text("One argument per line. These are appended after model, reasoning, and permissions flags.")
                            .font(DevysTypography.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
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

    private func optionalBinding(_ keyPath: WritableKeyPath<LauncherTemplate, String?>) -> Binding<String> {
        Binding(
            get: { template[keyPath: keyPath] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                template[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private var argumentsBinding: Binding<String> {
        Binding(
            get: { template.extraArguments.joined(separator: "\n") },
            set: { newValue in
                template.extraArguments = newValue
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

private struct StartupProfilesEditorView: View {
    @Environment(\.devysTheme) private var theme

    @Binding var profiles: [StartupProfile]
    @Binding var defaultProfileID: StartupProfile.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STARTUP PROFILES")
                        .font(DevysTypography.label)
                        .foregroundStyle(theme.text)
                    Text("Define multi-service startup profiles and choose the default Run behavior for a workspace.")
                        .font(DevysTypography.caption)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer()

                ActionButton("Add Profile", style: .ghost) {
                    let newProfile = StartupProfile(
                        displayName: "New Profile",
                        description: "",
                        steps: [
                            StartupProfileStep(displayName: "Step 1", command: "")
                        ]
                    )
                    profiles.append(newProfile)
                    if defaultProfileID == nil {
                        defaultProfileID = newProfile.id
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("default_run_profile")
                    .font(DevysTypography.label)
                    .foregroundStyle(theme.text)

                if profiles.isEmpty {
                    Text("Add a startup profile to enable the toolbar Run action.")
                        .font(DevysTypography.caption)
                        .foregroundStyle(theme.textSecondary)
                } else {
                    Picker("default_run_profile", selection: $defaultProfileID) {
                        Text("None").tag(Optional<StartupProfile.ID>.none)
                        ForEach(profiles) { profile in
                            Text(profile.displayName).tag(Optional(profile.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Text("The Run button launches this profile in the selected workspace.")
                        .font(DevysTypography.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            if profiles.isEmpty {
                Text("No startup profiles yet.")
                    .font(DevysTypography.body)
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextInput("Profile name", text: profileBinding(profile.id, \.displayName))

                            ActionButton(
                                defaultProfileID == profile.id ? "Default" : "Set Default",
                                style: defaultProfileID == profile.id ? .primary : .ghost
                            ) {
                                defaultProfileID = profile.id
                            }

                            ActionButton("Remove", style: .ghost, tone: .destructive) {
                                profiles.removeAll { $0.id == profile.id }
                                if defaultProfileID == profile.id {
                                    defaultProfileID = profiles.first?.id
                                }
                            }
                        }

                        TextInput(
                            "Description",
                            text: profileBinding(profile.id, \.description)
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(profile.steps.enumerated()), id: \.element.id) { stepIndex, step in
                                StartupProfileStepEditorView(
                                    step: stepBinding(profile.id, step.id)
                                ) {
                                    removeStep(step.id, from: profile.id)
                                }

                                if stepIndex < profile.steps.count - 1 {
                                    Separator()
                                }
                            }

                            ActionButton("Add Step", style: .ghost) {
                                appendStep(to: profile.id, count: profile.steps.count + 1)
                            }
                        }
                        .padding(12)
                        .elevation(.popover)
                    }
                    .padding(12)
                    .elevation(.card)

                    if index < profiles.count - 1 {
                        Separator()
                    }
                }
            }
        }
    }

    private func profileBinding<T>(
        _ profileID: StartupProfile.ID,
        _ keyPath: WritableKeyPath<StartupProfile, T>
    ) -> Binding<T> {
        Binding {
            profiles.first { $0.id == profileID }?[keyPath: keyPath]
                ?? profiles[0][keyPath: keyPath]
        } set: { newValue in
            guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
            profiles[index][keyPath: keyPath] = newValue
        }
    }

    private func stepBinding(
        _ profileID: StartupProfile.ID,
        _ stepID: StartupProfileStep.ID
    ) -> Binding<StartupProfileStep> {
        Binding {
            guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }),
                  let stepIndex = profiles[profileIndex].steps.firstIndex(where: { $0.id == stepID })
            else {
                return StartupProfileStep(displayName: "Missing", command: "")
            }
            return profiles[profileIndex].steps[stepIndex]
        } set: { newValue in
            guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }),
                  let stepIndex = profiles[profileIndex].steps.firstIndex(where: { $0.id == stepID })
            else { return }
            profiles[profileIndex].steps[stepIndex] = newValue
        }
    }

    private func appendStep(to profileID: StartupProfile.ID, count: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].steps.append(
            StartupProfileStep(
                displayName: "Step \(count)",
                command: ""
            )
        )
    }

    private func removeStep(_ stepID: StartupProfileStep.ID, from profileID: StartupProfile.ID) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[profileIndex].steps.removeAll { $0.id == stepID }
    }
}

private struct StartupProfileStepEditorView: View {
    @Environment(\.devysTheme) private var theme

    @Binding var step: StartupProfileStep
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextInput("Step name", text: $step.displayName)

                ActionButton("Remove", style: .ghost, tone: .destructive) {
                    onRemove()
                }
            }

            TextInput("Command", text: $step.command)

            TextInput("Working directory (relative to workspace)", text: $step.workingDirectory)

            Picker("launch_mode", selection: $step.launchMode) {
                ForEach(StartupProfileLaunchMode.allCases, id: \.self) { launchMode in
                    Text(launchMode.displayName).tag(launchMode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("environment")
                    .font(DevysTypography.label)
                    .foregroundStyle(theme.text)

                TextEditor(text: environmentBinding)
                    .font(DevysTypography.body)
                    .frame(minHeight: 64)
                    .padding(8)
                    .inputChrome(.base)

                Text("One KEY=value pair per line.")
                    .font(DevysTypography.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var environmentBinding: Binding<String> {
        Binding(
            get: {
                step.environment
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "\n")
            },
            set: { newValue in
                step.environment = parseEnvironment(newValue)
            }
        )
    }

    private func parseEnvironment(_ rawValue: String) -> [String: String] {
        rawValue
            .components(separatedBy: .newlines)
            .reduce(into: [:]) { partialResult, line in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty else { return }
                let parts = trimmedLine.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let firstPart = parts.first else { return }
                let key = String(firstPart).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }
                let value = parts.count == 2 ? String(parts[1]) : ""
                partialResult[key] = value
            }
    }
}

private extension LauncherExecutionBehavior {
    var displayName: String {
        switch self {
        case .runImmediately:
            return "Run Immediately"
        case .stageInTerminal:
            return "Stage In Terminal"
        }
    }
}

private extension StartupProfileLaunchMode {
    var displayName: String {
        switch self {
        case .newTab:
            return "New Tab"
        case .split:
            return "Split"
        case .backgroundManagedProcess:
            return "Background"
        }
    }
}
