import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The business's browser while this work item drives it: a line that opens the live view as a layer.
struct BrowserLine: View {
    let store: StoreOf<Workspace>
    let item: WorkItem
    @Dependency(\.browserClient) private var browser
    @State private var status: BrowserStatus?

    var body: some View {
        Group {
            if let status, status.open, status.driver == item.id {
                Button { store.send(.layerOpened(.browser(workID: item.id))) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe").foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                        Text(status.title ?? status.url ?? "Browser").lineLimit(1)
                        Spacer(minLength: 4)
                        Text("Watch").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                    }
                    .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .poll(id: item.id, every: .seconds(5)) { status = try? await browser.status(store.businessID) }
    }
}

/// While an employee drives the business's browser for this work item, a small live picture in its
/// thread (a new one every 2 seconds while it shows), with Watch and Take over. It is gone once the
/// browser is idle.
struct BrowserThumbnail: View {
    let store: StoreOf<Workspace>
    let workID: String
    @Dependency(\.browserClient) private var browser
    @State private var status: BrowserStatus?
    @State private var picture: BrowserPicture?

    private var item: WorkItem? { store.work.value?.first { $0.id == workID } }
    private var driving: Bool {
        guard let status, let item else { return false }
        return item.takenOverBy == nil && status.open && status.driving && status.driver == workID
    }

    var body: some View {
        Group {
            if driving {
                HStack(spacing: 12) {
                    Button(action: watch) {
                        Group {
                            if let data = picture?.data, let shown = PlatformImage(data: data) {
                                Image(platformImage: shown).resizable().scaledToFill()
                            } else {
                                DevysColors.sheetTint
                            }
                        }
                        .frame(width: 108, height: 68, alignment: .top)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Watch the browser")
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Browsing", systemImage: "globe").font(DevysTypography.control.weight(.semibold)).foregroundStyle(DevysColors.ink)
                        Text(status?.title ?? status?.url ?? "").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button("Watch", action: watch).buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    Button("Take over", systemImage: "hand.raised") { store.send(.takeOverTapped(workID)) }
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                }
                .devysCard(padding: 8)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            } else {
                // Something to hang the poll on while there is nothing to show.
                Color.clear.frame(height: 0)
            }
        }
        .poll(id: workID, every: .seconds(2)) {
            let businessID = store.businessID
            status = try? await browser.status(businessID)
            picture = driving ? try? await browser.picture(businessID) : nil
        }
    }

    private func watch() { store.send(.layerOpened(.browser(workID: workID))) }
}

/// The live picture of the business's browser, as a layer. Take over stops employees acting on
/// this work item; while it's yours, a tap on the picture clicks there and typed text goes to the
/// page. Closing the layer doesn't stop the browser.
struct BrowserLayer: View {
    let store: StoreOf<Workspace>
    let workID: String
    @Dependency(\.browserClient) private var browser
    @State private var picture: BrowserPicture?
    @State private var status: BrowserStatus?
    @State private var text = ""
    @State private var problem: String?

    private var current: WorkItem? { store.work.value?.first { $0.id == workID } }
    private var mine: Bool { current.map(store.state.isMine) ?? false }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "globe").foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                Text(status?.title ?? status?.url ?? "Browser").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2).lineLimit(1)
                Spacer(minLength: 8)
                if let current { TakeoverButton(store: store, item: current).buttonStyle(DevysButtonStyle(.quiet, compact: true)) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollView { image.frame(maxWidth: .infinity) }.background(DevysColors.sheetTint)
            Divider()
            footer.padding(12)
        }
        .poll(id: workID, every: .milliseconds(1_200)) {
            let businessID = store.businessID
            do {
                async let next = browser.status(businessID)
                async let shot = browser.picture(businessID)
                (status, picture) = try await (next, shot)
                problem = nil
            } catch {
                problem = failure("The browser couldn't be read.", error)
            }
        }
    }

    @ViewBuilder private var image: some View {
        if let picture, let data = picture.data, let shown = PlatformImage(data: data) {
            GeometryReader { geometry in
                Image(platformImage: shown).resizable().scaledToFit()
                    .onTapGesture { point in
                        guard mine else { return }
                        let scale = picture.width / max(geometry.size.width, 1)
                        send(.click(x: point.x * scale, y: point.y * scale))
                    }
                    .accessibilityLabel(status?.title ?? "The business's browser")
            }
            .aspectRatio(picture.width / max(picture.height, 1), contentMode: .fit)
        } else {
            Text(problem ?? "Loading…").font(DevysTypography.body).foregroundStyle(DevysColors.ink3).padding(20)
        }
    }

    @ViewBuilder private var footer: some View {
        if mine {
            HStack(spacing: 8) {
                FieldBox { TextField("Tap a field above, then type here", text: $text).onSubmit(typeText) }
                Button("Type", action: typeText).buttonStyle(DevysButtonStyle(.raised, compact: true))
                Button("Enter") { send(.key("Enter")) }.buttonStyle(DevysButtonStyle(.quiet, compact: true))
            }
        } else {
            Text("Take over to tap and type in this browser yourself; until then its employee drives it.")
                .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func typeText() {
        guard !text.isEmpty else { return }
        send(.type(text))
        text = ""
    }

    private func send(_ input: BrowserInput) {
        Task {
            do {
                try await browser.input(store.businessID, input)
            } catch {
                problem = "The page refused that. \(error.localizedDescription)"
            }
        }
    }
}

#if os(macOS)
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#else
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#endif
