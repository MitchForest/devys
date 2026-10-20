import Dependencies
import DevysClient
import DevysDesignSystem
public import SwiftUI
import TerminalCore
import TerminalSurface
import TerminalSurfaceCore

/// Which terminal a window shows; a window per session on the Mac and iPad.
public struct TerminalRef: Codable, Hashable, Sendable {
    public let businessID: String
    public let terminalID: String
    public let title: String

    public init(businessID: String, terminalID: String, title: String) {
        self.businessID = businessID
        self.terminalID = terminalID
        self.title = title
    }
}

/// A terminal on the owner's Mac: native Ghostty over the host session. Closing the window
/// leaves the session running; End closes it. Another device can attach and take control.
public struct TerminalWindow: View {
    let ref: TerminalRef
    var onClose: () -> Void = {}
    @Dependency(\.terminalsClient) private var terminals
    @State private var runtime: TerminalSurfaceRuntime?
    @State private var pty: RemoteTerminalPTY?
    @State private var state = RemoteTerminalState()
    @Environment(\.dismiss) private var dismiss

    public init(ref: TerminalRef) {
        self.ref = ref
    }

    init(ref: TerminalRef, onClose: @escaping () -> Void) {
        self.ref = ref
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let runtime {
                TerminalScreen(runtime: runtime)
            } else {
                Spacer()
            }
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone { keys }
            #endif
        }
        .background(DevysColors.sheet)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 320)
        .navigationTitle(ref.title)
        #endif
        .task { start() }
        .onDisappear { runtime?.terminate() }
    }

    private var status: String {
        if let code = state.exitCode { return code.map { "Ended (exit \($0))" } ?? "Ended" }
        if !state.connected { return "Connecting…" }
        return state.typing ? "Typing here" : "Watching: another device is typing"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(ref.title).font(DevysTypography.heading).lineLimit(1)
            Text(status).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).lineLimit(1)
            Spacer(minLength: 4)
            if state.connected, !state.typing, state.exitCode == nil {
                Button("Take control", systemImage: "hand.raised") { Task { await pty?.takeControl() } }
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
            }
            Button("End", systemImage: "xmark") {
                Task {
                    try? await terminals.close(ref.businessID, ref.terminalID)
                    close()
                }
            }
            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
            #if os(iOS)
            ToolbarIconButton("Close", symbol: "chevron.down") { close() }
            #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottomLeading) {
            if let problem = state.problem {
                Text(problem).font(DevysTypography.caption).foregroundStyle(DevysColors.ink2).padding(.horizontal, 12)
            }
        }
    }

    #if os(iOS)
    /// Keys a phone keyboard lacks.
    private var keys: some View {
        let keys: [(String, String)] = [
            ("esc", "\u{1b}"), ("tab", "\t"), ("^C", "\u{03}"), ("^D", "\u{04}"),
            ("←", "\u{1b}[D"), ("↑", "\u{1b}[A"), ("↓", "\u{1b}[B"), ("→", "\u{1b}[C")
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keys, id: \.0) { label, bytes in
                    Button(label) { send(bytes) }
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                        .accessibilityLabel(label == "^C" ? "Control C" : label == "^D" ? "Control D" : label)
                }
            }
            .padding(8)
        }
        .background(DevysColors.sheetTint)
    }
    #endif

    private func send(_ bytes: String) {
        guard let pty, let handle = UUID(uuidString: ref.terminalID).map(TerminalSessionHandle.init(id:)) else { return }
        Task { try? await pty.send(Data(bytes.utf8), to: handle) }
    }

    private func close() {
        onClose()
        dismiss()
    }

    private func start() {
        guard runtime == nil else { return }
        let terminals = self.terminals
        let ref = self.ref
        let pty = RemoteTerminalPTY(
            businessID: ref.businessID,
            terminalID: ref.terminalID,
            socketRequest: { offset in try await terminals.socket(ref.businessID, ref.terminalID, offset) },
            report: { next in Task { @MainActor in state = next } }
        )
        self.pty = pty
        runtime = TerminalSurfaceRuntime(
            terminalID: TerminalID(ref.terminalID),
            launchDescriptor: TerminalLaunchDescriptor(executablePath: "", arguments: []),
            callbacks: TerminalSurfaceCallbacks(),
            pty: pty
        )
    }
}

/// Opens a terminal in its own window where the platform has windows, and full screen otherwise.
struct TerminalOpener: ViewModifier {
    @Binding var presented: TerminalRef?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onChange(of: presented) { _, ref in
            guard let ref else { return }
            openWindow(value: ref)
            presented = nil
        }
        #else
        content
            .onChange(of: presented) { _, ref in
                guard let ref, supportsMultipleWindows, UIDevice.current.userInterfaceIdiom == .pad else { return }
                openWindow(value: ref)
                presented = nil
            }
            .fullScreenCover(item: Binding(
                get: { supportsMultipleWindows && UIDevice.current.userInterfaceIdiom == .pad ? nil : presented },
                set: { presented = $0 }
            )) { ref in
                TerminalWindow(ref: ref) { presented = nil }
            }
        #endif
    }
}

extension TerminalRef: Identifiable {
    public var id: String { terminalID }
}

/// The business's open terminals on the Mac, any of which this device can reopen, and a new one.
struct TerminalsSection: View {
    let businessID: String
    @Dependency(\.terminalsClient) private var terminals
    @State private var open: [TerminalInfo] = []
    @State private var presented: TerminalRef?

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.small) {
            HStack {
                SectionHeader("Terminals", count: open.count)
                Spacer(minLength: 4)
                Button("New terminal", systemImage: "terminal") {
                    Task { presented = await openTerminal(businessID, .business, terminals) }
                }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
            }
            ForEach(open) { terminal in
                Button {
                    presented = TerminalRef(businessID: businessID, terminalID: terminal.id, title: terminal.title)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal").foregroundStyle(DevysColors.ink3)
                        Text(terminal.title).font(DevysTypography.body).foregroundStyle(DevysColors.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(terminal.cwd).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).lineLimit(1).truncationMode(.head)
                    }
                    .devysCard()
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: businessID) {
            while !Task.isCancelled {
                open = ((try? await terminals.list(businessID)) ?? []).filter { $0.exit == nil }
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .modifier(TerminalOpener(presented: $presented))
    }
}
