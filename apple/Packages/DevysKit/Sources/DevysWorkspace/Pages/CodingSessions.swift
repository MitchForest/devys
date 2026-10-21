import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import DevysSurfaces
import SwiftUI

/// A work item's Codex and Claude Code sessions, read from the provider while shown; each
/// opens as a layer.
struct CodingSessions: View {
    let store: StoreOf<Workspace>
    let item: Commitment
    @Dependency(\.codingClient) private var coding
    @Dependency(\.terminalsClient) private var terminals
    @State private var sessions: [CodingSession] = []
    @State private var terminal: TerminalRef?
    @State private var problem: String?

    var body: some View {
        Group {
            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: DevysSpacing.small) {
                    HStack {
                        SectionHeader("Coding", count: sessions.count)
                        Spacer(minLength: 4)
                        if sessions.contains(where: { $0.purpose == "build" }) {
                            Button("Open terminal", systemImage: "terminal") {
                                Task { await openTerminal(store.businessID, .work(item.id), terminals, presented: $terminal, problem: $problem) }
                            }
                            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                        }
                    }
                    if let problem { Text(problem).font(DevysTypography.caption).foregroundStyle(DevysColors.ink2) }
                    ForEach(sessions) { session in
                        Button { store.send(.layerOpened(.session(workID: item.id, sessionID: session.id))) } label: { row(session) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: item.id) { await poll() }
        .modifier(TerminalOpener(presented: $terminal))
    }

    private func row(_ session: CodingSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
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

/// A coding session as a layer, read from the provider while it shows.
struct SessionLayer: View {
    let store: StoreOf<Workspace>
    let workID: String
    let sessionID: String
    @Dependency(\.codingClient) private var coding
    @State private var session: CodingSession?
    @State private var problem: String?

    var body: some View {
        Group {
            if let session, let item = store.work.value?.first(where: { $0.id == workID }) {
                SessionView(store: store, item: item, session: session)
            } else if let problem {
                EmptyNote(text: problem).padding(14)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: sessionID) {
            while !Task.isCancelled {
                do {
                    session = try await coding.sessions(store.businessID, workID).first { $0.id == sessionID }
                    problem = session == nil ? "This coding session no longer exists." : nil
                } catch {
                    problem = failure("The coding session couldn't be read.", error)
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

/// One coding session: its objective and latest reply, the running diff with line comments (the
/// web diff surface), and a composer that talks to the session once the owner has taken the work
/// over. Comments are always sendable: with the owner's message while they drive, otherwise as
/// one message in the work item's thread for its employee. Ask quotes the selected lines into
/// the conversation's composer.
private struct SessionView: View {
    let store: StoreOf<Workspace>
    let item: Commitment
    let session: CodingSession
    @Dependency(\.codingClient) private var coding
    @Dependency(\.terminalsClient) private var terminals
    @Dependency(\.runtimeClient) private var runtime
    @State private var terminal: TerminalRef?
    @State private var patch = ""
    @State private var selection: DiffSelection?
    @State private var draftComment = ""
    @State private var comments: [DiffComment] = []
    @State private var text = ""
    @State private var problem: String?

    private var current: Commitment { store.work.value?.first { $0.id == item.id } ?? item }
    private var mine: Bool { store.state.isMine(current) }
    private var owner: String { store.state.employeeName(current.ownerEmployeeID) }
    private var count: String { "\(comments.count) comment\(comments.count == 1 ? "" : "s")" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SurfaceView(.diff(patch: patch, comments: comments)) { selection = $0 }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer.padding(12)
        }
        .task(id: session.state) { await loadDiff() }
        .modifier(TerminalOpener(presented: $terminal))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(session.providerName + (session.purpose == "review" ? " · review" : "")).font(DevysTypography.heading)
                session.state.chip
                Spacer(minLength: 4)
            }
            HStack(spacing: 8) {
                Button("Open in \(session.providerName)", systemImage: "terminal") {
                    Task { await openTerminal(store.businessID, .resume(assignmentID: session.id), terminals, presented: $terminal, problem: $problem) }
                }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                if session.state == .working {
                    Button("Stop", systemImage: "stop.fill", action: stop)
                        .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                }
                TakeoverButton(store: store, item: current)
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
            }
            Text(session.branch ?? "").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).lineLimit(1)
                .help(session.worktree ?? "")
            if !session.objective.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Objective").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
                    Text(session.objective)
                        .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                        .lineLimit(4).textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
            if let reply = session.reply {
                ScrollView { MarkdownView(reply).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 140)
            } else if let error = session.error {
                Text(error).font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
            }
            SessionSteps(businessID: store.businessID, workID: item.id, session: session)
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
                    Button("Ask", systemImage: "quote.bubble") {
                        let lines = selection.start == selection.end ? "line \(selection.start)" : "lines \(selection.start)–\(selection.end)"
                        store.send(.askTapped("\(selection.path) \(lines)\n\(DiffComment.hunkText(patch, selection))"))
                        self.selection = nil
                    }
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                }
            }
            if !comments.isEmpty {
                if mine {
                    Text("\(count) will be sent with your message.").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                } else {
                    HStack(spacing: 8) {
                        Text("\(count) for \(owner), in this work item's thread.").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                        Button("Send \(count)", systemImage: "paperplane", action: sendComments)
                            .buttonStyle(DevysButtonStyle(.raised, compact: true))
                    }
                }
            }
            if mine {
                HStack(alignment: .bottom, spacing: 8) {
                    FieldBox { TextField("Tell \(session.providerName) what to do", text: $text, axis: .vertical).lineLimit(1...5) }
                    Button("Send", action: send).buttonStyle(DevysButtonStyle(.raised, compact: true))
                }
            } else if let takeover = store.state.takeoverTitle(current) {
                Text("\(takeover); they steer this session.").font(DevysTypography.body).foregroundStyle(DevysColors.ink3)
            } else {
                Text("Take over the work item to steer this session yourself; until then its employee steers it.")
                    .font(DevysTypography.body).foregroundStyle(DevysColors.ink3)
            }
            if let problem { Text(problem).font(DevysTypography.caption).foregroundStyle(DevysColors.ink2) }
        }
    }

    private func addComment() {
        guard let selection, !draftComment.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let text = draftComment.trimmingCharacters(in: .whitespacesAndNewlines)
        comments.append(DiffComment(selection, in: patch, base: session.baseCommit, text: text))
        draftComment = ""
        self.selection = nil
    }

    private func send() {
        let review = comments.isEmpty ? "" : DiffComment.review(current.title, comments)
        let message = [review, text.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }.joined(separator: "\n")
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

    /// Until the owner drives, comments go to the work item's employee as one message in its thread.
    private func sendComments() {
        guard !comments.isEmpty else { return }
        let key = ConversationKey.work(item.id)
        let message = NewMessage(id: UUID().uuidString.lowercased(), text: DiffComment.review(current.title, comments), mentions: [current.ownerEmployeeID])
        let owner = owner
        Task {
            do {
                let posted = try await runtime.postMessage(store.businessID, key, message)
                store.send(Workspace.Action(.conversation(.posted(key, clientID: message.id, posted))))
                comments = []
                problem = nil
            } catch DevysHTTPError.rejected(status: 409, _) {
                problem = "\(owner) is paused, so the comments weren't sent."
            } catch {
                problem = "The comments couldn't be sent."
            }
        }
    }

    private func stop() {
        Task {
            do {
                try await coding.stop(store.businessID, item.id, session.id)
                problem = nil
            } catch {
                problem = failure("Couldn't stop \(session.providerName).", error)
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

/// Opens a terminal on the Mac and presents the window that shows it, or says why it couldn't.
func openTerminal(
    _ businessID: String,
    _ target: TerminalTarget,
    _ terminals: TerminalsClient,
    presented: Binding<TerminalRef?>,
    problem: Binding<String?>
) async {
    do {
        let opened = try await terminals.open(businessID, target)
        problem.wrappedValue = nil
        presented.wrappedValue = TerminalRef(businessID: businessID, terminalID: opened.id, title: opened.title)
    } catch {
        problem.wrappedValue = failure("The Mac couldn't open a terminal.", error)
    }
}

/// What failed, then why, in the workspace's words for server errors.
func failure(_ what: String, _ error: any Error) -> String {
    guard let error = error as? DevysHTTPError else { return "\(what) Try again." }
    return "\(what) \(Workspace.message(for: error))"
}

/// What the session actually did, closed until asked for: read from the harness each time it
/// opens (and while it works), never kept by Devys.
private struct SessionSteps: View {
    let businessID: String
    let workID: String
    let session: CodingSession
    @Dependency(\.codingClient) private var coding
    @State private var open = false
    @State private var entries: [TranscriptEntry]?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(open ? "Hide details" : "Details") { open.toggle() }
                .buttonStyle(.plain).font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            if open {
                if let problem {
                    Text(problem).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                } else if let entries {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in step(entry) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                } else {
                    ProgressView()
                }
            }
        }
        .task(id: open ? "\(session.id):\(session.state)" : nil) { await load() }
    }

    private func load() async {
        guard open else { return }
        repeat {
            do {
                entries = try await coding.transcript(businessID, workID, session.id)
                problem = nil
            } catch {
                problem = error.localizedDescription
            }
            guard session.state == .working else { return }
            try? await Task.sleep(for: .seconds(5))
        } while !Task.isCancelled
    }

    private func step(_ entry: TranscriptEntry) -> some View {
        let label = switch entry.kind {
        case .prompt: "Told"
        case .reply: "Said"
        case .plan: "Plan"
        case .command: "Ran"
        case .files: "Edited"
        case .tool: "Used"
        }
        return VStack(alignment: .leading, spacing: 1) {
            Text(label).font(DevysTypography.caption).foregroundStyle(entry.failed == true ? DevysColors.red : DevysColors.ink3)
            Text(entry.text)
                .font(entry.kind == .command || entry.kind == .files ? DevysTypography.caption.monospaced() : DevysTypography.secondary)
                .foregroundStyle(DevysColors.ink2).lineLimit(6).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
