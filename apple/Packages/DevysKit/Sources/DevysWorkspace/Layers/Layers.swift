import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The layer on top of the right panel.
struct LayerView: View {
    let store: StoreOf<Workspace>
    let layer: Layer

    var body: some View {
        switch layer {
        case .work(let id):
            WorkLayer(store: store, workID: id)
        case .artifact(let id, let updatedBy):
            ArtifactLayer(store: store, artifactID: id, updatedBy: updatedBy)
        case .file(let path):
            // A finished turn reads the file again: an employee may have just changed it.
            FileView(store: store, file: FileEntry(name: (path as NSString).lastPathComponent, path: path, kind: .file))
                .id("\(path):\(store.turns)")
        case .session(let workID, let sessionID):
            SessionLayer(store: store, workID: workID, sessionID: sessionID)
        case .browser(let workID):
            BrowserLayer(store: store, workID: workID)
        case .routine(let id):
            RoutineLayer(store: store, routineID: id)
        case .remoteApp(let id):
            RemoteAppLayer(store: store, appID: id)
        }
    }
}

/// A page an employee published, following its versions: a new version arriving in the
/// conversation replaces the one on screen and says who changed it.
private struct ArtifactLayer: View {
    let store: StoreOf<Workspace>
    let artifactID: String
    let updatedBy: String?

    var body: some View {
        let current = store.artifacts.first { $0.id == artifactID }
        let versions = current.map { page in store.artifacts.filter { $0.filename == page.filename }.sorted { $0.createdAt < $1.createdAt } } ?? []
        let index = versions.firstIndex { $0.id == artifactID } ?? 0
        VStack(spacing: 0) {
            if versions.count > 1 || updatedBy != nil {
                HStack(spacing: 6) {
                    if versions.count > 1 {
                        Button("Earlier version", systemImage: "chevron.left") { store.send(.layerReplaced(.artifact(versions[index - 1].id))) }
                            .disabled(index == 0)
                        Text("v\(index + 1) of \(versions.count)").monospacedDigit()
                        Button("Later version", systemImage: "chevron.right") { store.send(.layerReplaced(.artifact(versions[index + 1].id))) }
                            .disabled(index >= versions.count - 1)
                    }
                    if let updatedBy {
                        Text("Updated by \(updatedBy)").foregroundStyle(DevysColors.indigo).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(DevysTypography.caption)
                .foregroundStyle(DevysColors.ink3)
                .padding(.horizontal, 12)
                .frame(height: 36)
                Rectangle().fill(DevysColors.hairline).frame(height: 1)
            }
            PublishedPage(businessID: store.businessID, artifactID: artifactID).id(artifactID)
        }
    }
}

/// The business folder's machine folders, hidden at its root: repositories and coding worktrees
/// nobody browses (the Mac host lays them out: src/apps/code/host/worktree.ts).
let machineFolders: Set<String> = ["repos", "worktrees"]

extension FileKind {
    var symbol: String {
        switch self {
        case .markdown: "doc.richtext"
        case .pdf: "doc.text"
        case .image: "photo"
        case .office: "doc"
        case .sheet: "tablecells"
        case .whiteboard: "scribble"
        case .text: "chevron.left.forwardslash.chevron.right"
        case .other: "doc"
        }
    }
}

/// A work item beside the conversation, whichever it is: its card (the plan, what its employee is
/// doing now, the one thing asked of the owner, the results), then what was said about it, and a
/// field to reply to whoever is on it.
private struct WorkLayer: View {
    let store: StoreOf<Workspace>
    let workID: String
    @FocusState private var focused: Bool

    private var key: ConversationKey { .work(workID) }

    var body: some View {
        let owner = store.work.value?.first { $0.id == workID }.map { store.state.employeeName($0.ownerEmployeeID) }
        VStack(spacing: 0) {
            WorkProgressCard(store: store, workItemID: workID)
            ScrollView {
                ConversationMessages(store: store, key: key)
                    .padding(.horizontal, DevysSpacing.regular)
                    .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    "Reply to \(owner ?? "them")",
                    text: Binding(get: { store.state.conversation(key)?.draft ?? "" }, set: { store.send(.draftChanged(key, $0)) }),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(DevysTypography.body)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit { store.send(.sendTapped(key)) }
                .padding(.vertical, 6)
                Button("Send", systemImage: "arrow.up") { store.send(.sendTapped(key)) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(DevysColors.indigo, in: Circle())
                    .disabled((store.state.conversation(key)?.draft ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(10)
        }
    }
}
