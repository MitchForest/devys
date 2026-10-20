package import DevysClient
import Foundation

/// Merges dictated speech into text the owner already typed, without
/// duplicating segments. Ported from devys-macos-ios MacSpeechTranscriptionDraft.
package struct TranscriptionDraft: Equatable, Sendable {
    private let initialText: String

    package init(initialText: String = "") {
        self.initialText = initialText
    }

    package func merged(finalized: String, volatile: String) -> String {
        merge(Self.append(volatile, to: finalized))
    }

    package func merged(_ transcript: String) -> String {
        merge(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func merge(_ transcript: String) -> String {
        let initial = initialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !initial.isEmpty else { return transcript }
        guard !transcript.isEmpty else { return initialText }
        let separator = initialText.last?.isWhitespace == true ? "" : " "
        return initialText + separator + transcript
    }

    private static func append(_ segment: String, to transcript: String) -> String {
        let segment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else { return transcript }
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return segment }
        return transcript + " " + segment
    }
}

/// What the microphone and voice are doing right now.
package enum VoicePhase: Equatable, Sendable {
    case idle
    case starting(SpeechMode)
    case listening(SpeechMode)
    case finishing(SpeechMode)
    /// Hands-free: the turn was sent (this id: client, then server) and its answer is awaited.
    case awaitingReply(messageID: String)
    case speaking

    package var mode: SpeechMode? {
        switch self {
        case .starting(let mode), .listening(let mode), .finishing(let mode): mode
        default: nil
        }
    }

    package var isCapturing: Bool { mode != nil }
}

extension SpeechCaptureError {
    var message: String {
        switch self {
        case .microphoneDenied: "Devys needs microphone access. Turn it on in System Settings › Privacy & Security › Microphone."
        case .speechDenied: "Devys needs speech recognition. Turn it on in System Settings › Privacy & Security › Speech Recognition."
        case .unsupportedLocale: "On-device speech isn't available for your language yet."
        case .modelUnavailable: "The speech model couldn't be downloaded. Check the connection and try again."
        case .interrupted: "Listening stopped because another app took the microphone."
        case .timeLimit: "Listening stopped at the time limit."
        case .noSpeech: "Didn't catch anything."
        case .cancelled: ""
        case .unavailable: "Speech isn't available right now."
        }
    }
}
