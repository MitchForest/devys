import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

/// A scripted microphone: tests emit events and decide what finishing returns.
private actor ScriptedMicrophone {
    var sinks: [UUID: AsyncThrowingStream<SpeechCaptureEvent, any Error>.Continuation] = [:]
    var starts: [SpeechMode] = []
    var results: [String] = []
    var failure: SpeechCaptureError?

    func start(_ id: UUID, _ mode: SpeechMode) throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        if let failure { throw failure }
        starts.append(mode)
        let (stream, sink) = AsyncThrowingStream<SpeechCaptureEvent, any Error>.makeStream()
        sinks[id] = sink
        return stream
    }

    func emit(_ event: SpeechCaptureEvent) {
        for sink in sinks.values { sink.yield(event) }
    }

    func finish(_ id: UUID) throws -> String {
        sinks.removeValue(forKey: id)?.finish()
        guard !results.isEmpty else { throw SpeechCaptureError.noSpeech }
        return results.removeFirst()
    }

    func queue(_ text: String) { results.append(text) }
    func fail(with error: SpeechCaptureError) { failure = error }
    func failListening(_ error: SpeechCaptureError) {
        for sink in sinks.values { sink.finish(throwing: error) }
        sinks.removeAll()
    }
}

/// The Chief of Staff's DM as the server keeps it: each posted message, then the Chief of Staff's answer once one is set.
private actor Conversation {
    var posted: [NewMessage] = []
    var messages: [ConversationMessage] = []
    var spoken: [String] = []
    var reactions: [(EmployeeScope, Reaction)] = []
    var reply: String?
    var failPosts = false

    private func make(_ author: String, _ text: String, replyTo: String? = nil, viaVoice: Bool = false) -> ConversationMessage {
        ConversationMessage(
            id: "m\(messages.count + 1)",
            conversation: "direct:ops",
            author: author,
            text: text,
            replyTo: replyTo,
            viaVoice: viaVoice,
            createdAt: ServerDate.format(Date(timeIntervalSince1970: 1_792_400_000 + Double(messages.count)))
        )
    }

    func post(_ message: NewMessage) throws -> PostedMessage {
        if failPosts { throw DevysHTTPError.unreachable("offline") }
        posted.append(message)
        let mine = make("person:person-preview", message.text, replyTo: message.replyTo, viaVoice: message.viaVoice)
        messages.append(mine)
        if let reply { messages.append(make("employee:ops", reply)) }
        return PostedMessage(message: mine, recipients: ["ops"])
    }

    func speak(_ text: String) { spoken.append(text) }
    func react(_ scope: EmployeeScope, _ reaction: Reaction) { reactions.append((scope, reaction)) }
    func setFailPosts(_ fail: Bool) { failPosts = fail }

    /// Answers whatever is waiting, then every later message.
    func setReply(_ text: String) {
        reply = text
        if messages.last?.isFromPerson == true { messages.append(make("employee:ops", text)) }
    }

    func page() -> ConversationPage { ConversationPage(messages: messages, respondent: "ops") }

    func status() -> EmployeeStatus {
        let waiting = messages.last?.isFromPerson == true
        return EmployeeStatus(state: RuntimeState(run: waiting ? .init(id: "r", stopped: false, deadline: nil) : nil, inbox: [], outbox: []))
    }
}

@MainActor
@Suite("Voice and chat")
struct VoiceFeatureTests {
    private func makeStore(microphone: ScriptedMicrophone, conversation: Conversation) async -> StoreOf<Workspace> {
        let store: StoreOf<Workspace> = withDependencies {
            $0.speechCaptureClient = SpeechCaptureClient(
                start: { try await microphone.start($0, $1) },
                finish: { try await microphone.finish($0) },
                cancel: { _ in }
            )
            $0.speechPlaybackClient = SpeechPlaybackClient(
                voices: { [] },
                speak: { text, _, _ in await conversation.speak(text) },
                stop: {}
            )
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { BusinessDetail.fixture($0) },
                status: { _ in await conversation.status() },
                stop: { _ in true },
                memory: { _ in [] },
                conversation: { _, _, _ in await conversation.page() },
                postMessage: { _, _, message in try await conversation.post(message) },
                react: { await conversation.react($0, $1) }
            )
            $0.sessionClient = .unimplemented
            $0.continuousClock = ImmediateClockStandIn()
            $0.uuid = .incrementing
        } operation: {
            Store(initialState: Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)) { Workspace() }
        }
        await settle("team") { store.chiefOfStaffScope != nil }
        store.send(.message("ops"))
        await settle("The Chief of Staff's DM") { store.main?.messages.value != nil }
        return store
    }

    private let key = ConversationKey.direct("ops")

    private func draft(_ store: StoreOf<Workspace>) -> String { store.main?.draft ?? "" }

    private func settle(_ what: String, _ condition: @MainActor () async -> Bool) async {
        for _ in 0..<20_000 {
            if await condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for \(what)")
    }

    @Test("Dictation flows into the open conversation's draft after typed text and doesn't send")
    func dictation() async {
        let microphone = ScriptedMicrophone()
        let conversation = Conversation()
        let store = await makeStore(microphone: microphone, conversation: conversation)
        store.send(.draftChanged(key, "Note:"))
        store.send(.micTapped)
        await settle("listening") { await microphone.starts == [.dictation] }
        await microphone.emit(.listening)
        await microphone.emit(.transcript(finalized: "launch is on track", volatile: "for"))
        await settle("draft") { draft(store) == "Note: launch is on track" }
        #expect(store.volatileText == "for")
        await microphone.queue("launch is on track for November")
        store.send(.micTapped)
        await settle("finished") { store.voice == .idle }
        #expect(draft(store) == "Note: launch is on track for November")
        #expect(await conversation.posted.isEmpty)
    }

    @Test("Sending while still dictating marks the message as dictated")
    func sendMidDictation() async {
        let microphone = ScriptedMicrophone()
        let conversation = Conversation()
        let store = await makeStore(microphone: microphone, conversation: conversation)
        store.send(.micTapped)
        await settle("listening") { await microphone.starts == [.dictation] }
        await microphone.emit(.transcript(finalized: "what is due today", volatile: ""))
        await settle("draft") { draft(store) == "what is due today" }
        store.send(.sendTapped(key))
        await settle("sent") { await conversation.posted.count == 1 }
        #expect(await conversation.posted.first?.viaVoice == true)
        #expect(store.voice == .idle)
    }

    @Test("Hands-free listens, sends into the open conversation, speaks the answer, then listens again")
    func conversationLoop() async {
        let microphone = ScriptedMicrophone()
        let conversation = Conversation()
        let store = await makeStore(microphone: microphone, conversation: conversation)
        store.send(.conversationToggled)
        await settle("first turn") { await microphone.starts == [.handsFree] }
        await microphone.emit(.listening)
        await microphone.queue("What's blocking launch?")
        await microphone.emit(.endOfSpeech)
        await settle("sent") { await conversation.posted.count == 1 }
        await settle("awaiting") { if case .awaitingReply = store.voice { true } else { false } }
        await conversation.setReply("The domain quote.")
        await settle("spoken") { await conversation.spoken == ["The domain quote."] }
        await settle("second turn") { await microphone.starts == [.handsFree, .handsFree] }
        #expect(store.isConversationMode)
        #expect(store.main?.pending.isEmpty == true)
        #expect(await conversation.posted.first?.viaVoice == true)
    }

    @Test("Silence in a conversation keeps listening instead of failing")
    func silenceRestarts() async {
        let microphone = ScriptedMicrophone()
        let store = await makeStore(microphone: microphone, conversation: Conversation())
        store.send(.conversationToggled)
        await settle("first turn") { await microphone.starts.count == 1 }
        await microphone.failListening(.noSpeech)
        await settle("restart") { await microphone.starts.count == 2 }
        #expect(store.voiceError == nil)
    }

    @Test("A denied microphone ends the conversation and says how to fix it")
    func denied() async {
        let microphone = ScriptedMicrophone()
        await microphone.fail(with: .microphoneDenied)
        let store = await makeStore(microphone: microphone, conversation: Conversation())
        store.send(.conversationToggled)
        await settle("error") { store.voiceError != nil }
        #expect(!store.isConversationMode)
        #expect(store.voiceError?.contains("Microphone") == true)
    }

    @Test("Leaving the conversation ends hands-free")
    func leavingEndsHandsFree() async {
        let microphone = ScriptedMicrophone()
        let store = await makeStore(microphone: microphone, conversation: Conversation())
        store.send(.conversationToggled)
        await settle("first turn") { await microphone.starts.count == 1 }
        store.send(.message("growth"))
        #expect(!store.isConversationMode)
        #expect(store.voice == .idle)
        #expect(store.main?.key == .direct("growth"))
    }

    @Test("Reactions replace each other and go to the message's author")
    func reactions() async {
        let conversation = Conversation()
        await conversation.setReply("Draft ready.")
        let store = await makeStore(microphone: ScriptedMicrophone(), conversation: conversation)
        store.send(.draftChanged(key, "First"))
        store.send(.sendTapped(key))
        await settle("answered") { store.main?.messages.value?.count == 2 && store.main?.pending.isEmpty == true }
        store.send(.reactionTapped(key, "m2", "👍"))
        #expect(store.main?.messages.value?.last?.reactions == ["👍"])
        store.send(.reactionTapped(key, "m2", "❤️"))
        #expect(store.main?.messages.value?.last?.reactions == ["❤️"])
        // The owner's own message takes no tapback.
        store.send(.reactionTapped(key, "m1", "👍"))
        #expect(store.main?.messages.value?.first?.reactions.isEmpty == true)
        await settle("reactions sent") { await conversation.reactions.count == 3 }
        let sent = await conversation.reactions
        #expect(sent.map(\.1.isOn) == [true, false, true])
        #expect(sent.allSatisfy { $0.0 == EmployeeScope(businessID: "acme", employeeID: "ops") && $0.1.targetID == "m2" })
    }

    @Test("A failed send stays visible and retries with the same id")
    func retry() async {
        let conversation = Conversation()
        await conversation.setFailPosts(true)
        let store = await makeStore(microphone: ScriptedMicrophone(), conversation: conversation)
        store.send(.draftChanged(key, "Hello"))
        store.send(.sendTapped(key))
        await settle("failed") { store.main?.pending.first?.failed == true }
        let id = store.main?.pending.first?.id ?? ""
        await conversation.setFailPosts(false)
        store.send(.retryTapped(key, id))
        await settle("posted") { store.main?.pending.isEmpty == true }
        #expect(await conversation.posted.map(\.id) == [id])
        #expect(store.main?.messages.value?.map(\.text) == ["Hello"])
    }

    @Test("Typed messages appear immediately and become the posted message")
    func typedSend() async {
        let conversation = Conversation()
        let store = await makeStore(microphone: ScriptedMicrophone(), conversation: conversation)
        store.send(.draftChanged(key, "  Draft the inquiry  "))
        store.send(.sendTapped(key))
        #expect(store.main?.pending.map(\.text) == ["Draft the inquiry"])
        #expect(draft(store).isEmpty)
        await settle("posted") { store.main?.pending.isEmpty == true }
        #expect(await conversation.posted.map(\.text) == ["Draft the inquiry"])
        #expect(await conversation.posted.first?.viaVoice == false)
        #expect(store.main?.messages.value?.last?.text == "Draft the inquiry")
    }

    @Test("Dictated text merges without duplicating segments")
    func draftMerge() {
        let draft = TranscriptionDraft(initialText: "Hello ")
        #expect(draft.merged(finalized: "team", volatile: "how") == "Hello team how")
        #expect(TranscriptionDraft().merged(finalized: "", volatile: "").isEmpty)
        #expect(TranscriptionDraft(initialText: "Hi").merged("there") == "Hi there")
    }
}

/// Sleeps return at once so reply polling runs without real delays.
struct ImmediateClockStandIn: Clock {
    typealias Duration = Swift.Duration
    struct Instant: InstantProtocol {
        var offset: Duration = .zero
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    var now: Instant { Instant() }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}
