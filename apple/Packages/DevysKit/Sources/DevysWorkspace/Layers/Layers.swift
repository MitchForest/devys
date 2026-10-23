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
