import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation

// MARK: - Voice in the main pane's conversation: dictation and the hands-free loop

extension Workspace {
    func reduceVoice(_ intent: Intent, state: inout State) {
        switch intent {
        case .micTapped:
            guard state.main != nil else { return }
            switch state.voice {
            case .idle: startCapture(.dictation, state: &state)
            case .listening(.dictation), .starting(.dictation): finishCapture(&state)
            default: break
            }

        case .conversationToggled:
            guard state.main != nil || state.isConversationMode else { return }
            state.isConversationMode.toggle()
            if state.isConversationMode {
                if state.voice == .idle { startCapture(.handsFree, state: &state) }
            } else {
                endConversation(&state)
            }

        case .speechEvent(let id, let event):
            speechEvent(id, event, state: &state)

        case .speechFinished(let id, let text):
            speechFinished(id, text: text, state: &state)

        case .speechFailed(let id, let error):
            speechFailed(id, error: error, state: &state)

        case .speakingFinished:
            guard state.voice == .speaking else { return }
            state.voice = .idle
            if state.isConversationMode { startCapture(.handsFree, state: &state) }

        case .stopSpeakingTapped:
            let playback = playback
            store.addTask { await playback.stop() }

        case .voiceErrorDismissed:
            state.voiceError = nil

        default:
            break
        }
    }

    func speechEvent(_ id: UUID, _ event: SpeechCaptureEvent, state: inout State) {
        guard id == state.captureID else { return }
        switch event {
        case .listening:
            if let mode = state.voice.mode { state.voice = .listening(mode) }
        case .transcript(let finalized, let volatile):
            state.volatileText = volatile
            if state.voice.mode != .handsFree, let key = state.main?.key {
                let draft = state.dictationBase.merged(finalized: finalized, volatile: "")
                update(key, &state) { conversation in
                    conversation.draft = draft
                    // Sending mid-dictation still tells the employee the words were spoken.
                    if !finalized.isEmpty { conversation.draftUsedVoice = true }
                }
            }
        case .level(let level):
            state.level = level
        case .endOfSpeech:
            finishCapture(&state)
        case .requestingPermission, .downloadingModel, .preparing:
            break
        }
    }

    func speechFinished(_ id: UUID, text: String, state: inout State) {
        guard id == state.captureID else { return }
        let mode = state.voice.mode
        state.captureID = nil
        state.volatileText = ""
        state.level = 0
        switch mode {
        case .dictation:
            state.voice = .idle
            guard let key = state.main?.key else { return }
            let draft = state.dictationBase.merged(text)
            update(key, &state) { conversation in
                conversation.draft = draft
                conversation.draftUsedVoice = conversation.draftUsedVoice || !text.isEmpty
            }
        case .handsFree:
            let sent = state.main.flatMap { send(text, viaVoice: true, in: $0.key, state: &state) }
            state.voice = sent.map { .awaitingReply(messageID: $0) } ?? .idle
        case nil:
            state.voice = .idle
        }
    }

    func speechFailed(_ id: UUID, error: SpeechCaptureError, state: inout State) {
        guard id == state.captureID else { return }
        let mode = state.voice.mode
        state.captureID = nil
        state.volatileText = ""
        state.level = 0
        state.voice = .idle
        if mode == .handsFree, state.isConversationMode, error == .noSpeech || error == .timeLimit {
            // Silence is normal in a conversation; keep listening.
            startCapture(.handsFree, state: &state)
            return
        }
        if error != .cancelled, error != .noSpeech { state.voiceError = error.message }
        if [.microphoneDenied, .speechDenied, .unsupportedLocale, .modelUnavailable].contains(error) {
            state.isConversationMode = false
        }
    }

    func startCapture(_ mode: SpeechMode, state: inout State) {
        let id = uuid()
        state.captureID = id
        state.voice = .starting(mode)
        state.voiceError = nil
        state.volatileText = ""
        state.dictationBase = TranscriptionDraft(initialText: mode == .handsFree ? "" : state.main?.draft ?? "")
        let capture = capture
        store.addTask {
            do {
                for try await event in try await capture.start(id, mode) {
                    try store.send(Action(.speechEvent(id, event)))
                }
            } catch let error as SpeechCaptureError {
                try store.send(Action(.speechFailed(id, error)))
            }
        }
    }

    func finishCapture(_ state: inout State) {
        guard let id = state.captureID, let mode = state.voice.mode else { return }
        state.voice = .finishing(mode)
        let capture = capture
        store.addTask {
            do {
                let text = try await capture.finish(id)
                try store.send(Action(.speechFinished(id, text)))
            } catch let error as SpeechCaptureError {
                try store.send(Action(.speechFailed(id, error)))
            }
        }
    }

    func cancelCapture(_ state: inout State) {
        guard let id = state.captureID else { return }
        state.captureID = nil
        state.voice = .idle
        state.volatileText = ""
        state.level = 0
        let capture = capture
        store.addTask { await capture.cancel(id) }
    }

    func endConversation(_ state: inout State) {
        state.isConversationMode = false
        if state.voice.isCapturing { cancelCapture(&state) }
        if state.voice == .speaking {
            let playback = playback
            store.addTask { await playback.stop() }
        }
        state.voice = .idle
    }
}
