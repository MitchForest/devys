import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import DevysSurfaces
import SwiftUI

/// A work item's Codex and Claude Code sessions, read from the provider while shown; each
/// opens its session view.
struct CodingSessions: View {
    let store: StoreOf<Workspace>
    let item: Commitment
    @Dependency(\.codingClient) private var coding
    @Dependency(\.terminalsClient) private var terminals
    @State private var sessions: [CodingSession] = []
    @State private var open: CodingSession?
    @State private var terminal: TerminalRef?

    var body: some View {
        Group {
            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: DevysSpacing.small) {
                    HStack {
                        SectionHeader("Coding", count: sessions.count)
                        Spacer(minLength: 4)
                        if sessions.contains(where: { $0.purpose == "build" }) {
                            Button("Open terminal", systemImage: "terminal") {
                                Task { terminal = await openTerminal(store.businessID, .work(item.id), terminals) }
                            }
                            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                        }
                    }
                    ForEach(sessions) { session in
                        Button { open = session } label: { row(session) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: item.id) { await poll() }
        .modifier(TerminalOpener(presented: $terminal))
        .sheet(item: $open) { session in
            SessionScreen(store: store, item: item, session: sessions.first { $0.id == session.id } ?? session)
        }
    }

    private func row(_ session: CodingSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(DevysColors.ink3)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.providerName + (session.purpose == "review" ? " · review" : ""))
                    .font(DevysTypography.body).foregroundStyle(DevysColors.ink)
                Text("\(session.branch ?? "") · \(session.changeLine)")
                    .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).lineLimit(1)
            }
            Spacer(minLength: 6)
            session.state.chip
        }
        .devysCard()
    }

    private func poll() async {
        while !Task.isCancelled {
            if let loaded = try? await coding.sessions(store.businessID, item.id) { sessions = loaded }
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

/// One coding session: its latest reply, the running diff with line comments (the web diff
/// surface), and a composer that talks to the session once the owner has taken the work over.
struct SessionScreen: View {
    let store: StoreOf<Workspace>
    let item: Commitment
    let session: CodingSession
    @Dependency(\.codingClient) private var coding
    @Dependency(\.terminalsClient) private var terminals
    @Environment(\.dismiss) private var dismiss
    @State private var terminal: TerminalRef?
    @State private var patch = ""
    @State private var selection: DiffSelection?
    @State private var draftComment = ""
    @State private var comments: [DiffComment] = []
    @State private var text = ""
    @State private var problem: String?

    private var current: Commitment { store.work.value?.first { $0.id == item.id } ?? item }
    private var mine: Bool { current.takenOverBy != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SurfaceView(.diff(patch: patch, comments: comments)) { selection = $0 }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer.padding(12)
        }
        #if os(macOS)
        .frame(minWidth: 820, idealWidth: 1100, minHeight: 600, idealHeight: 800)
        #endif
        .task(id: session.state) { await loadDiff() }
        .modifier(TerminalOpener(presented: $terminal))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(session.providerName + (session.purpose == "review" ? " · review" : "")).font(DevysTypography.heading)
                session.state.chip
                Spacer(minLength: 4)
                Button("Open in \(session.providerName)", systemImage: "terminal") {
                    Task { terminal = await openTerminal(store.businessID, .resume(assignmentID: session.id), terminals) }
                }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                if session.state == .working {
                    Button("Stop", systemImage: "stop.fill") { Task { try? await coding.stop(store.businessID, item.id, session.id) } }
                        .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                }
                Button(mine ? "Hand back" : "Take over", systemImage: mine ? "arrowshape.turn.up.left" : "hand.raised") {
                    store.send(.takeoverToggled(item.id))
                }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                ToolbarIconButton("Close", symbol: "xmark") { dismiss() }
            }
            Text("\(session.branch ?? "") · \(session.worktree ?? "")").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).lineLimit(1)
            if let reply = session.reply {
                ScrollView { MarkdownView(reply).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 140)
            } else if let error = session.error {
                Text(error).font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
            }
        }
        .padding(14)
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selection {
                HStack(spacing: 8) {
                    Text("\(selection.path) \(selection.start == selection.end ? "line \(selection.start)" : "lines \(selection.start)–\(selection.end)")")
                        .font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                    FieldBox { TextField("Comment on these lines", text: $draftComment).onSubmit(addComment) }
                    Button("Add", action: addComment).buttonStyle(DevysButtonStyle(.raised, compact: true))
                }
            }
            if !comments.isEmpty {
                Text("\(comments.count) comment\(comments.count == 1 ? "" : "s") will be sent with your message.")
                    .font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
            }
            if mine {
                HStack(alignment: .bottom, spacing: 8) {
                    FieldBox { TextField("Tell \(session.providerName) what to do", text: $text, axis: .vertical).lineLimit(1...5) }
                    Button("Send", action: send).buttonStyle(DevysButtonStyle(.raised, compact: true))
                }
            } else {
                Text("Take over the work item to steer this session yourself; until then its employee steers it.")
                    .font(DevysTypography.body).foregroundStyle(DevysColors.ink3)
            }
            if let problem { Text(problem).font(DevysTypography.caption).foregroundStyle(DevysColors.ink2) }
        }
    }

    private func addComment() {
        guard let selection, !draftComment.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        comments.append(DiffComment(path: selection.path, side: selection.side, start: selection.start, end: selection.end, text: draftComment))
        draftComment = ""
        self.selection = nil
    }

    private func send() {
        let lines = (comments.isEmpty ? [] : ["Review comments:"] + comments.map { "- \($0.line)" }) + [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        let message = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        guard !message.isEmpty else { return }
        Task {
            do {
                try await coding.steer(store.businessID, item.id, session.id, message)
                text = ""
                comments = []
                problem = nil
            } catch {
                problem = "That couldn't be sent."
            }
        }
    }

    private func loadDiff() async {
        while !Task.isCancelled {
            if let diff = try? await coding.diff(store.businessID, item.id, session.id) { patch = diff.patch }
            try? await Task.sleep(for: .seconds(session.state == .working ? 5 : 30))
        }
    }
}

extension CodingSession.State {
    var chip: StatusChip {
        switch self {
        case .working: StatusChip("Working", tone: .inProgress)
        case .idle: StatusChip("Turn finished", tone: .done)
        case .interrupted: StatusChip("Interrupted", tone: .waiting)
        case .failed: StatusChip("Failed", tone: .failed)
        case .unavailable: StatusChip("Mac host unavailable", tone: .waiting)
        }
    }
}

/// Opens a terminal on the Mac and names the window that will show it; nil if the Mac refused.
func openTerminal(_ businessID: String, _ target: TerminalTarget, _ terminals: TerminalsClient) async -> TerminalRef? {
    guard let opened = try? await terminals.open(businessID, target) else { return nil }
    return TerminalRef(businessID: businessID, terminalID: opened.id, title: opened.title)
}
