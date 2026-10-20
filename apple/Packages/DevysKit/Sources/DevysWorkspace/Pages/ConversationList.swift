import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// iPhone's Home: the greeting, then Direct messages and Spaces with unread counts,
/// then what needs the owner. Each conversation opens full screen.
struct CompactHome: View {
    let store: StoreOf<Workspace>

    var body: some View {
        PageBody {
            TodayGreeting(store: store)
            if let count = store.decisions.value?.count, count > 0 {
                Button { store.send(.pageSelected(.approvals)) } label: {
                    Label("\(count) waiting for your approval", systemImage: "faceid")
                        .font(DevysTypography.control)
                        .foregroundStyle(DevysColors.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .devysCard(padding: DevysSpacing.compact)
                }
                .buttonStyle(.plain)
            }
            ConversationList(store: store)
            TodayWork(store: store)
        }
    }
}

/// Every employee's DM and every space, each with its newest message and unread count.
struct ConversationList: View {
    let store: StoreOf<Workspace>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader("Direct messages").padding(.bottom, 4)
            ForEach(store.snapshot.employees) { employee in
                let key = ConversationKey.direct(employee.id)
                ConversationRow(
                    title: employee.name,
                    preview: preview(key, working: store.state.isWorking(employee.id) ? employee : nil),
                    unread: store.state.unread(key)
                ) {
                    Portrait(store.state.portrait(for: employee), size: 36, mood: store.state.mood(for: employee), isAnimated: false)
                } open: {
                    store.send(.pageSelected(.direct(employee.id)))
                }
            }
        }
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionHeader("Spaces")
                Spacer()
                NewSpaceButton(store: store)
            }
            .padding(.bottom, 4)
            if (store.spaces.value ?? []).isEmpty { EmptyNote(text: "No spaces yet. A space keeps one area of the business in one conversation.") }
            ForEach(store.spaces.value ?? []) { space in
                let key = ConversationKey.space(space.id)
                ConversationRow(title: space.name, preview: preview(key, working: nil), unread: store.state.unread(key)) {
                    BusinessTile(String(space.name.prefix(1)), tint: .blue, size: 36)
                } open: {
                    store.send(.pageSelected(.space(space.id)))
                }
            }
        }
    }

    /// The newest message, attributed; a working employee says so instead.
    private func preview(_ key: ConversationKey, working: Employee?) -> String {
        if let working { return "\(working.name) is working…" }
        guard let last = store.state.summaries[key.rawValue]?.last else { return "No messages yet" }
        if last.isEvent { return last.text }
        if let employee = last.employeeID, key.kind != .direct { return "\(store.state.employeeName(employee)): \(last.text)" }
        return last.isFromPerson ? "You: \(last.text)" : last.text
    }
}

private struct ConversationRow<Leading: View>: View {
    let title: String
    let preview: String
    let unread: Int
    @ViewBuilder let leading: Leading
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DevysTypography.body.weight(unread > 0 ? .semibold : .regular)).foregroundStyle(DevysColors.ink)
                    Text(preview).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).lineLimit(1)
                }
                Spacer(minLength: 8)
                if unread > 0 { UnreadBadge(count: unread) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unread > 0 ? "\(title), \(unread) unread, \(preview)" : "\(title), \(preview)")
    }
}
