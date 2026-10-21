import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The business's browser while this work item drives it: a line that opens the live view.
struct BrowserLine: View {
    let store: StoreOf<Workspace>
    let item: Commitment
    @Dependency(\.browserClient) private var browser
    @State private var status: BrowserStatus?
    @State private var watching = false

    var body: some View {
        Group {
            if let status, status.open, status.driver == item.id {
                Button { watching = true } label: {
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
                .sheet(isPresented: $watching) { BrowserSheet(store: store, item: item) }
            }
        }
        .task(id: item.id) {
            while !Task.isCancelled {
                status = try? await browser.status(store.businessID)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

/// The live picture of the business's browser. Take over stops employees acting on this work
/// item; while it's yours, a tap on the picture clicks there and typed text goes to the page.
private struct BrowserSheet: View {
    let store: StoreOf<Workspace>
    let item: Commitment
    @Dependency(\.browserClient) private var browser
    @Environment(\.dismiss) private var dismiss
    @State private var picture: BrowserPicture?
    @State private var status: BrowserStatus?
    @State private var text = ""
    @State private var problem: String?

    private var current: Commitment { store.work.value?.first { $0.id == item.id } ?? item }
    private var mine: Bool { store.state.isMine(current) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "globe").foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                Text(status?.title ?? "Browser").font(DevysTypography.heading).foregroundStyle(DevysColors.ink).lineLimit(1)
                Spacer(minLength: 8)
                TakeoverButton(store: store, item: current).buttonStyle(DevysButtonStyle(.quiet, compact: true))
                ToolbarIconButton("Close", symbol: "xmark") { dismiss() }
            }
            .padding(12)
            Divider()
            ScrollView { image.frame(maxWidth: .infinity) }.background(DevysColors.sheetTint)
            Divider()
            footer.padding(12)
        }
        .frame(minWidth: 720, minHeight: 560)
        .task {
            while !Task.isCancelled {
                let businessID = store.businessID
                do {
                    async let next = browser.status(businessID)
                    async let shot = browser.picture(businessID)
                    (status, picture) = try await (next, shot)
                } catch {
                    problem = error.localizedDescription
                }
                try? await Task.sleep(for: .milliseconds(1_200))
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
