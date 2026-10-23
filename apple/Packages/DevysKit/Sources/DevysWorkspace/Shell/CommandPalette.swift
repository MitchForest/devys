import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// ⌘K: jump to an employee, a project, a thread or a page in the current business by typing.
struct CommandPalette: View {
    let store: StoreOf<Workspace>
    @State private var query = ""
    @FocusState private var focused: Bool

    private struct Target: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let action: Workspace.Action
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { store.send(.paletteToggled(false)) }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                    TextField("Search people, projects, threads and pages", text: $query)
                        .textFieldStyle(.plain)
                        .font(DevysTypography.heading.weight(.regular))
                        .focused($focused)
                        .onSubmit { if let first = results.first { go(first.action) } }
                }
                .padding(16)
                Rectangle().fill(DevysColors.hairline).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(results) { target in
                            Button { go(target.action) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: target.symbol).frame(width: 20).foregroundStyle(DevysColors.ink2).accessibilityHidden(true)
                                    Text(target.title).foregroundStyle(DevysColors.ink)
                                    Spacer()
                                    Text(target.detail).foregroundStyle(DevysColors.ink3)
                                }
                                .font(DevysTypography.control)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(target.id == results.first?.id ? DevysColors.sheetTint : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if results.isEmpty {
                            Text("No matches").font(DevysTypography.body).foregroundStyle(DevysColors.ink3).padding(12)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 320)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, DevysSpacing.regular)
            .background(DevysColors.sheet, in: RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous))
            .devysElevation(.raised)
            .padding(.top, 90)
        }
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            store.send(.paletteToggled(false))
            return .handled
        }
    }

    private var targets: [Target] {
        var all = store.snapshot.employees.map { employee in
            Target(id: "dm-\(employee.id)", title: employee.name, detail: RoleTemplate.displayName(employee.template), symbol: "bubble.left", action: .message(employee.id))
        }
        all += (store.projects.value ?? []).map { Target(id: $0.id, title: $0.name, detail: "Project", symbol: "square.grid.2x2", action: .placeSelected(.project($0.id))) }
        all += (store.work.value ?? []).filter(\.state.isOpen).map { Target(id: $0.id, title: $0.title, detail: "Thread", symbol: "checklist", action: .threadOpened($0.id)) }
        all += store.artifacts.filter { $0.contentType == "text/html" && $0.latestID == $0.id }.map { page in
            Target(id: "page-\(page.id)", title: store.state.artifactName(page.id), detail: "Page", symbol: "doc.richtext", action: .layerOpened(.artifact(page.id)))
        }
        return all
    }

    private var results: [Target] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return targets }
        return targets.filter { $0.title.lowercased().contains(needle) || $0.detail.lowercased().contains(needle) }
    }

    private func go(_ action: Workspace.Action) {
        store.send(action)
        store.send(.paletteToggled(false))
    }
}
