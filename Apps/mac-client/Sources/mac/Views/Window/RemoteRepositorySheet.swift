import AppFeatures
import Foundation
import RemoteCore
import SwiftUI
import UI

struct RemoteRepositorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let initialAuthority: RemoteRepositoryAuthority?
    let recentAuthorities: [RemoteRepositoryAuthority]
    let onSave: (RemoteRepositoryAuthority) -> Void
    let onCancel: () -> Void

    @State private var sshTarget: String
    @State private var displayName: String
    @State private var repositoryPath: String
    @State private var sshConfigHosts: [SSHConfigHostOption] = []

    init(
        initialAuthority: RemoteRepositoryAuthority?,
        recentAuthorities: [RemoteRepositoryAuthority],
        onSave: @escaping (RemoteRepositoryAuthority) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialAuthority = initialAuthority
        self.recentAuthorities = recentAuthorities
        self.onSave = onSave
        self.onCancel = onCancel
        _sshTarget = State(initialValue: initialAuthority?.sshTarget ?? "")
        _displayName = State(initialValue: initialAuthority?.displayName ?? "")
        _repositoryPath = State(initialValue: initialAuthority?.repositoryPath ?? "")
    }

    var body: some View {
        Sheet(
            title: initialAuthority == nil ? "Connect Over SSH" : "Edit SSH Repository",
            primaryAction: SheetAction(
                title: initialAuthority == nil ? "Save Repository" : "Update Repository",
                isEnabled: isSaveEnabled,
                action: save
            ),
            secondaryAction: SheetAction(title: "Cancel", action: cancel),
            onDismiss: cancel
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.space4) {
                    intro
                    hostSection
                    repositorySection
                    nicknameSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .task {
                if sshConfigHosts.isEmpty {
                    sshConfigHosts = SSHConfigHostDiscovery.loadHosts()
                }
            }
        }
        .frame(width: 680, height: 720)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Spacing.space2) {
            Text("Pick a saved host or paste a one-off `user@host`, then choose the repository path on that machine.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)

            Text("Devys uses the macOS `ssh` executable and works best with SSH config aliases plus key or agent auth.")
                .font(Typography.caption)
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var hostSection: some View {
        sectionCard(
            title: "1. Choose a Host",
            detail: "Recent SSH targets and hosts discovered from `~/.ssh/config`."
        ) {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                FormField("SSH Host") {
                    TextInput("mac-mini or user@host", text: $sshTarget, icon: "server.rack")
                }

                if let selectedHost = selectedSSHConfigHost {
                    infoPill(
                        icon: "checkmark.circle",
                        title: "Using saved host \(selectedHost.alias)",
                        detail: selectedHost.detailLine
                    )
                }

                suggestionGroup(
                    title: "Recent Hosts",
                    items: filteredRecentHosts,
                    emptyMessage: sshTarget.isEmpty ? "No recent SSH targets yet." : nil
                ) { host in
                    applyHostSuggestion(host.sshTarget)
                } label: { host in
                    suggestionRow(
                        title: host.sshTarget,
                        subtitle: host.displayName,
                        icon: "clock.arrow.circlepath"
                    )
                }

                suggestionGroup(
                    title: "SSH Config",
                    items: filteredSSHConfigHosts,
                    emptyMessage: sshConfigHosts.isEmpty ? "No saved hosts found in `~/.ssh/config`." : nil
                ) { host in
                    applyHostSuggestion(host.alias)
                } label: { host in
                    suggestionRow(
                        title: host.alias,
                        subtitle: host.detailLine,
                        icon: "list.bullet.rectangle"
                    )
                }
            }
        }
    }

    private var repositorySection: some View {
        sectionCard(
            title: "2. Choose a Repository",
            detail: "Use a recent remote repository for this host or enter the path manually."
        ) {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                FormField("Repository Path") {
                    TextInput("~/Code/devys", text: $repositoryPath, icon: "folder")
                }

                if filteredRecentRepositories.isEmpty {
                    Text("No saved repository paths for this host yet.")
                        .font(Typography.caption)
                        .foregroundStyle(theme.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.space2) {
                        Text("Recent Repositories on This Host")
                            .font(Typography.caption.weight(.semibold))
                            .foregroundStyle(theme.textSecondary)

                        VStack(spacing: Spacing.space2) {
                            ForEach(filteredRecentRepositories) { authority in
                                Button {
                                    sshTarget = authority.sshTarget
                                    repositoryPath = authority.repositoryPath
                                    if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        displayName = authority.displayName
                                    }
                                } label: {
                                    suggestionRow(
                                        title: authority.displayName,
                                        subtitle: authority.repositoryPath,
                                        icon: "shippingbox"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    infoPill(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "Rail label preview",
                        detail: "\(resolvedDisplayName) (\(resolvedHostLabel))"
                    )
                }
            }
        }
    }

    private var nicknameSection: some View {
        sectionCard(
            title: "3. Name It",
            detail: "Optional. Leave this blank to use the repository folder name."
        ) {
            FormField("Nickname") {
                TextInput("devys", text: $displayName, icon: "pencil.line")
            }
        }
    }
}

private extension RemoteRepositorySheet {
    private var isSaveEnabled: Bool {
        !sshTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedSSHConfigHost: SSHConfigHostOption? {
        let normalizedTarget = normalized(sshTarget)
        guard !normalizedTarget.isEmpty else { return nil }
        return sshConfigHosts.first { normalized($0.alias) == normalizedTarget }
    }

    private var filteredRecentHosts: [RemoteRepositoryAuthority] {
        let normalizedTarget = normalized(sshTarget)
        var seenTargets: Set<String> = []
        return recentAuthorities.filter { authority in
            let target = normalized(authority.sshTarget)
            guard seenTargets.insert(target).inserted else { return false }
            guard !normalizedTarget.isEmpty else { return true }
            return target.contains(normalizedTarget)
                || normalized(authority.displayName).contains(normalizedTarget)
        }
    }

    private var filteredSSHConfigHosts: [SSHConfigHostOption] {
        let normalizedTarget = normalized(sshTarget)
        return sshConfigHosts.filter { host in
            guard !normalizedTarget.isEmpty else { return true }
            return normalized(host.alias).contains(normalizedTarget)
                || normalized(host.detailLine).contains(normalizedTarget)
        }
    }

    private var filteredRecentRepositories: [RemoteRepositoryAuthority] {
        let normalizedTarget = normalized(sshTarget)
        guard !normalizedTarget.isEmpty else { return [] }
        return recentAuthorities.filter { authority in
            normalized(authority.sshTarget) == normalizedTarget
        }
    }

    private var resolvedDisplayName: String {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplayName.isEmpty {
            return trimmedDisplayName
        }
        let trimmedPath = repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "Repository" }
        return URL(fileURLWithPath: trimmedPath).lastPathComponent
    }

    private var resolvedHostLabel: String {
        let trimmedTarget = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTarget.isEmpty ? "host" : trimmedTarget
    }

    private func sectionCard<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            VStack(alignment: .leading, spacing: Spacing.space1) {
                Text(title)
                    .font(Typography.heading)
                    .foregroundStyle(theme.text)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
            }

            content()
        }
        .padding(Spacing.space4)
        .background(theme.card, in: DevysShape())
        .overlay {
            DevysShape()
                .stroke(theme.border, lineWidth: Spacing.borderWidth)
        }
    }

    private func suggestionGroup<Item: Identifiable, Label: View>(
        title: String,
        items: [Item],
        emptyMessage: String?,
        onSelect: @escaping (Item) -> Void,
        @ViewBuilder label: @escaping (Item) -> Label
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space2) {
            Text(title)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)

            if items.isEmpty {
                if let emptyMessage {
                    Text(emptyMessage)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            } else {
                VStack(spacing: Spacing.space2) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            label(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func suggestionRow(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: Spacing.space3) {
            Image(systemName: icon)
                .font(Typography.caption.weight(.medium))
                .foregroundStyle(theme.accent)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(theme.text)
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.space3)
        .padding(.vertical, Spacing.space2)
        .background(theme.base, in: DevysShape())
        .overlay {
            DevysShape()
                .stroke(theme.border, lineWidth: Spacing.borderWidth)
        }
        .contentShape(DevysShape())
    }

    private func infoPill(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: Spacing.space2) {
            Image(systemName: icon)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(theme.text)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.space3)
        .padding(.vertical, Spacing.space2)
        .background(theme.accentSubtle, in: DevysShape())
    }

    private func applyHostSuggestion(
        _ suggestedHost: String
    ) {
        sshTarget = suggestedHost
        if let recentRepository = filteredRecentRepositories.first,
           repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            repositoryPath = recentRepository.repositoryPath
        }
    }

    private func save() {
        guard isSaveEnabled else { return }
        let authority = RemoteRepositoryAuthority(
            sshTarget: sshTarget,
            displayName: displayName,
            repositoryPath: repositoryPath
        )
        onSave(authority)
        dismiss()
    }

    private func cancel() {
        onCancel()
        dismiss()
    }

    private func normalized(
        _ value: String
    ) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
