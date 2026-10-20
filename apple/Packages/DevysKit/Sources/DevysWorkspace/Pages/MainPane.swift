import ComposableArchitecture2
import DevysDesignSystem
import SwiftUI

/// Routes the main pane. Each page owns its header and any tabs it needs.
struct MainPane: View {
    let store: StoreOf<Workspace>

    var body: some View {
        ZStack(alignment: .top) {
            PageContent(store: store, page: store.page)
                .id(store.page)
            if let notice = store.notice {
                NoticeBanner(text: notice) { store.send(.noticeDismissed) }
                    .padding(.top, DevysSpacing.compact)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(DevysMotion.arrive, value: store.page)
        .animation(DevysMotion.quick, value: store.notice)
    }
}

/// One page's content; iPhone pushes these from its home list.
struct PageContent: View {
    let store: StoreOf<Workspace>
    let page: Page

    var body: some View {
        switch page {
        case .today: TodayPage(store: store)
        case .approvals: ApprovalsPage(store: store)
        case .files(let path): FilesPage(store: store, path: path)
        case .direct(let id): DirectPage(store: store, employeeID: id)
        case .space(let id): SpacePage(store: store, spaceID: id)
        case .employee(let id): EmployeePage(store: store, employeeID: id)
        case .inbox: InboxPage()
        case .work(let filter): WorkPage(store: store, filter: filter)
        case .money: MoneyPage(store: store)
        case .apps(let section): AppsPage(store: store, section: section)
        }
    }
}

private struct NoticeBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(DevysTypography.body).foregroundStyle(DevysColors.ink)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(DevysColors.ink3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(DevysColors.sheet, in: Capsule())
        .devysElevation(.raised)
    }
}
