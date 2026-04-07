// RepositoryPortLabelsEditorView.swift
// Devys - Repository-scoped static port label editor.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Workspace
import UI

struct RepositoryPortLabelsEditorView: View {
    @Environment(\.devysTheme) private var theme

    @Binding var labels: [RepositoryPortLabel]
    @State private var drafts: [RepositoryPortLabelDraft] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if drafts.isEmpty {
                Text("No static port labels yet.")
                    .font(DevysTypography.sm)
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach($drafts) { $draft in
                    PortLabelDraftRow(
                        draft: $draft,
                        validationMessage: validationMessage(for: draft),
                        onRemove: {
                            drafts.removeAll { $0.id == draft.id }
                            persistDraftsIfValid()
                        },
                        onChange: persistDraftsIfValid
                    )
                }
            }
        }
        .onAppear {
            syncDraftsFromLabels()
        }
        .onChange(of: labels) { _, _ in
            syncDraftsFromLabels()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("PORT LABELS")
                    .font(DevysTypography.label)
                    .foregroundStyle(theme.text)
                Text("Static labels augment detected workspace ports and update immediately when valid.")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            Button("Add Label") {
                drafts.append(RepositoryPortLabelDraft())
                persistDraftsIfValid()
            }
            .buttonStyle(.bordered)
        }
    }

    private func syncDraftsFromLabels() {
        let nextDrafts = labels.map(RepositoryPortLabelDraft.init(label:))
        if nextDrafts != drafts {
            drafts = nextDrafts
        }
    }

    private func persistDraftsIfValid() {
        let duplicatePorts = duplicatePortIDs()
        let resolved = drafts.compactMap { draft -> RepositoryPortLabel? in
            guard !duplicatePorts.contains(draft.id) else { return nil }
            return draft.resolvedLabel
        }

        guard resolved.count == drafts.count else { return }
        labels = resolved
    }

    private func validationMessage(for draft: RepositoryPortLabelDraft) -> String? {
        if duplicatePortIDs().contains(draft.id) {
            return "Each port can only have one static label."
        }

        if draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a label name."
        }

        guard let port = Int(draft.portText), (1...65535).contains(port) else {
            return "Port must be a number between 1 and 65535."
        }

        let scheme = draft.scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty else {
            return "Enter a URL scheme such as http or https."
        }

        if scheme.contains(where: { !$0.isLetter }) {
            return "Scheme should only contain letters."
        }

        _ = port
        return nil
    }

    private func duplicatePortIDs() -> Set<RepositoryPortLabel.ID> {
        let resolvedByPort = drafts.reduce(into: [Int: [RepositoryPortLabel.ID]]()) { partialResult, draft in
            guard let port = Int(draft.portText), (1...65535).contains(port) else { return }
            partialResult[port, default: []].append(draft.id)
        }

        return resolvedByPort.values.reduce(into: Set<RepositoryPortLabel.ID>()) { partialResult, ids in
            if ids.count > 1 {
                partialResult.formUnion(ids)
            }
        }
    }
}

private struct PortLabelDraftRow: View {
    @Environment(\.devysTheme) private var theme

    @Binding var draft: RepositoryPortLabelDraft
    let validationMessage: String?
    let onRemove: () -> Void
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Label", text: $draft.label)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draft.label) { _, _ in
                        onChange()
                    }

                TextField("Port", text: $draft.portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                    .onChange(of: draft.portText) { _, _ in
                        onChange()
                    }

                Button("Remove") {
                    onRemove()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DevysColors.error)
            }

            HStack {
                TextField("Scheme", text: $draft.scheme)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draft.scheme) { _, _ in
                        onChange()
                    }

                TextField("Optional path", text: $draft.path)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draft.path) { _, _ in
                        onChange()
                    }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(DevysTypography.xs)
                    .foregroundStyle(DevysColors.warning)
            }
        }
        .padding(12)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
    }
}

private struct RepositoryPortLabelDraft: Identifiable, Equatable {
    let id: RepositoryPortLabel.ID
    var portText: String
    var label: String
    var scheme: String
    var path: String

    init(
        id: RepositoryPortLabel.ID = UUID(),
        portText: String = "",
        label: String = "",
        scheme: String = "http",
        path: String = ""
    ) {
        self.id = id
        self.portText = portText
        self.label = label
        self.scheme = scheme
        self.path = path
    }

    init(label: RepositoryPortLabel) {
        self.init(
            id: label.id,
            portText: String(label.port),
            label: label.label,
            scheme: label.scheme,
            path: label.path
        )
    }

    var resolvedLabel: RepositoryPortLabel? {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedScheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty,
              !trimmedScheme.isEmpty,
              trimmedScheme.allSatisfy(\.isLetter),
              let port = Int(portText),
              (1...65535).contains(port)
        else {
            return nil
        }

        return RepositoryPortLabel(
            id: id,
            port: port,
            label: trimmedLabel,
            scheme: trimmedScheme.lowercased(),
            path: path.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
