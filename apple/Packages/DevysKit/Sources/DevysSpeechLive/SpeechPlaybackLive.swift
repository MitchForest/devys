public import DevysClient
import AVFAudio
import Foundation
import Synchronization

// Ported from scribble-2's DeviceSpeechPlayback: delegate events are keyed to the
// utterance that produced them, so a late callback from a stopped reply cannot
// settle the next one; voices are ranked premium > enhanced > default.
extension SpeechPlaybackClient {
    public static func live() -> Self {
        let player = SpeechPlayer()
        return Self(
            voices: { SpeechVoices.ranked().map(SpeechVoices.describe) },
            speak: { text, voiceID, rate in try await player.speak(text, voiceID: voiceID, rate: rate) },
            stop: { await player.stop() }
        )
    }
}

enum SpeechVoices {
    static func ranked() -> [AVSpeechSynthesisVoice] {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let preferred = AVSpeechSynthesisVoice(language: language)?.identifier
        return AVSpeechSynthesisVoice.speechVoices()
            .filter {
                $0.language == language
                    && !$0.voiceTraits.contains(.isNoveltyVoice)
                    && !$0.voiceTraits.contains(.isPersonalVoice)
                    && !$0.identifier.hasPrefix("com.apple.speech.synthesis.voice.")
            }
            .sorted {
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                if ($0.identifier == preferred) != ($1.identifier == preferred) { return $0.identifier == preferred }
                return $0.name < $1.name
            }
    }

    static func describe(_ voice: AVSpeechSynthesisVoice) -> SpeechVoice {
        let quality = switch voice.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Default"
        }
        return SpeechVoice(id: voice.identifier, name: voice.name, quality: quality, language: voice.language)
    }
}

private actor SpeechPlayer {
    private let synthesizer = AVSpeechSynthesizer()
    private let relay = SpeechRelay()

    init() {
        synthesizer.delegate = relay
    }

    func speak(_ text: String, voiceID: String?, rate: Double) async throws {
        try Task.checkCancellation()
        let voice = voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? SpeechVoices.ranked().first
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(min(max(rate, 0.5), 1.5))
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let (events, continuation) = AsyncStream<SpeechRelay.Event>.makeStream()
        relay.register(utterance, continuation: continuation)
        defer {
            relay.remove(utterance)
            continuation.finish()
        }
        synthesizer.speak(utterance)
        try await withTaskCancellationHandler {
            for await event in events {
                switch event {
                case .started: continue
                case .finished: return
                case .cancelled: throw CancellationError()
                }
            }
            throw CancellationError()
        } onCancel: {
            continuation.finish()
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .word)
    }
}

final class SpeechRelay: NSObject, AVSpeechSynthesizerDelegate, Sendable {
    enum Event: Sendable { case started, finished, cancelled }

    private struct Registration: Sendable {
        let id: ObjectIdentifier
        let continuation: AsyncStream<Event>.Continuation
    }

    private let current = Mutex<Registration?>(nil)

    func register(_ utterance: AVSpeechUtterance, continuation: AsyncStream<Event>.Continuation) {
        let id = ObjectIdentifier(utterance)
        current.withLock { $0 = Registration(id: id, continuation: continuation) }
    }

    func remove(_ utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        current.withLock { if $0?.id == id { $0 = nil } }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        emit(.started, utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        emit(.finished, utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        emit(.cancelled, utterance)
    }

    private func emit(_ event: Event, _ utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        current.withLock { $0?.id == id ? $0?.continuation : nil }?.yield(event)
    }
}
