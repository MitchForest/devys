import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The live picture of the business's browser, as a layer. On the Mac it is a watch-only preview:
/// the owner works in the business's own Chrome window (Open Chrome brings it to the front) and
/// hands back on the work card. On iPhone and iPad, while the work is theirs, a tap on the picture
/// clicks there and typed text goes to the page. Closing the layer doesn't stop the browser.
struct BrowserLayer: View {
    let store: StoreOf<Workspace>
    let workID: String
    @Dependency(\.browserClient) private var browser
    @State private var picture: BrowserPicture?
    @State private var status: BrowserStatus?
    @State private var problem: String?
    #if os(iOS)
        @State private var text = ""
    #endif

    private var current: WorkItem? { store.work.value?.first { $0.id == workID } }
    private var mine: Bool { current.map(store.state.isMine) ?? false }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "globe").foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                Text(status?.title ?? status?.url ?? "Browser").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2).lineLimit(1)
                Spacer(minLength: 8)
                if let current { control(current) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollView { image.frame(maxWidth: .infinity) }.background(DevysColors.sheetTint)
            #if os(iOS)
                Divider()
                footer.padding(12)
            #endif
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

    /// Open Chrome takes the work over and brings Chrome to the front (the Mac); Take over makes
    /// the picture touchable (iPhone and iPad). Hand back returns it to its employee.
    @ViewBuilder private func control(_ item: WorkItem) -> some View {
        #if os(macOS)
            if mine {
                Button("Hand back", systemImage: "arrowshape.turn.up.left") { store.send(.takeoverToggled(item.id)) }
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
            } else if item.takenOverBy == nil, item.state.isOpen {
                Button("Open Chrome", systemImage: "macwindow") { store.send(.takeOverTapped(item.id)) }
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
            }
        #else
            TakeoverButton(store: store, item: item).buttonStyle(DevysButtonStyle(.quiet, compact: true))
        #endif
    }

    @ViewBuilder private var image: some View {
        if let picture, let data = picture.data, let shown = PlatformImage(data: data) {
            GeometryReader { geometry in
                Image(platformImage: shown).resizable().scaledToFit()
                    #if os(iOS)
                    .onTapGesture { point in
                        guard mine else { return }
                        let scale = picture.width / max(geometry.size.width, 1)
                        send(.click(x: point.x * scale, y: point.y * scale))
                    }
                    #endif
                    .accessibilityLabel(status?.title ?? "The business's browser")
            }
            .aspectRatio(picture.width / max(picture.height, 1), contentMode: .fit)
        } else {
            Text(problem ?? "Loading…").font(DevysTypography.body).foregroundStyle(DevysColors.ink3).padding(20)
        }
    }

    #if os(iOS)
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
    #endif
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
