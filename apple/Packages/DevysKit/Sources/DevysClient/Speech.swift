public import Dependencies
public import Foundation

/// How the microphone is being used.
public enum SpeechMode: Sendable, Equatable {
    /// Words flow into the composer until you stop.
    case dictation
    /// A conversation turn that ends on its own when you stop speaking.
    case handsFree

    package var maximumSeconds: Double {
        switch self {
        case .dictation: 300
        case .handsFree: 60
        }
    }

    /// Silence after speech that ends a turn; nil means only you end it.
    package var pauseSeconds: Double? { self == .handsFree ? 1.2 : nil }
}

public enum SpeechCaptureEvent: Equatable, Sendable {
    case requestingPermission
    case downloadingModel
    case preparing
    case listening
    /// Settled words, plus the latest provisional guess that may still change.
    case transcript(finalized: String, volatile: String)
    case level(Double)
    case endOfSpeech
}

public enum SpeechCaptureError: Error, Hashable, Sendable {
    case microphoneDenied, speechDenied, unsupportedLocale, modelUnavailable
    case interrupted, cancelled, noSpeech, timeLimit, unavailable
}

/// On-device speech-to-text. One session at a time, identified by the caller.
public struct SpeechCaptureClient: Sendable {
    public var start: @Sendable (UUID, SpeechMode) async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error>
    /// Ends input and returns the transcript, waiting at most a few seconds for finalization.
    public var finish: @Sendable (UUID) async throws -> String
    public var cancel: @Sendable (UUID) async -> Void

    public init(
        start: @escaping @Sendable (UUID, SpeechMode) async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error>,
        finish: @escaping @Sendable (UUID) async throws -> String,
        cancel: @escaping @Sendable (UUID) async -> Void
    ) {
        self.start = start
        self.finish = finish
        self.cancel = cancel
    }

    public static let unavailable = Self(
        start: { _, _ in throw SpeechCaptureError.unavailable },
        finish: { _ in throw SpeechCaptureError.unavailable },
        cancel: { _ in }
    )
}

public struct SpeechVoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// "Premium", "Enhanced" or "Default".
    public let quality: String
    public let language: String

    public init(id: String, name: String, quality: String, language: String) {
        self.id = id
        self.name = name
        self.quality = quality
        self.language = language
    }
}

/// On-device text-to-speech with the installed system voices.
public struct SpeechPlaybackClient: Sendable {
    /// Installed voices for the current language, best quality first.
    public var voices: @Sendable () -> [SpeechVoice]
    /// Speaks and returns when finished; throws if stopped or unavailable.
    public var speak: @Sendable (_ text: String, _ voiceID: String?, _ rate: Double) async throws -> Void
    public var stop: @Sendable () async -> Void

    public init(
        voices: @escaping @Sendable () -> [SpeechVoice],
        speak: @escaping @Sendable (String, String?, Double) async throws -> Void,
        stop: @escaping @Sendable () async -> Void
    ) {
        self.voices = voices
        self.speak = speak
        self.stop = stop
    }

    public static let silent = Self(voices: { [] }, speak: { _, _, _ in }, stop: {})
}

/// Voice preferences, stored per device because installed voices differ.
public struct VoiceSettings: Equatable, Sendable, Codable {
    public var voiceID: String?
    /// 0.5–1.5 times the system's default speaking rate.
    public var rate: Double
    /// Read the Chief of Staff's replies aloud.
    public var speaksReplies: Bool

    public init(voiceID: String? = nil, rate: Double = 1, speaksReplies: Bool = false) {
        self.voiceID = voiceID
        self.rate = rate
        self.speaksReplies = speaksReplies
    }
}

public struct VoiceSettingsClient: Sendable {
    public var load: @Sendable () -> VoiceSettings
    public var save: @Sendable (VoiceSettings) -> Void

    public init(load: @escaping @Sendable () -> VoiceSettings, save: @escaping @Sendable (VoiceSettings) -> Void) {
        self.load = load
        self.save = save
    }

    public static let userDefaults = Self(
        load: {
            UserDefaults.standard.data(forKey: "voiceSettings")
                .flatMap { try? JSONDecoder().decode(VoiceSettings.self, from: $0) } ?? VoiceSettings()
        },
        save: { settings in
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "voiceSettings") }
        }
    )

    public static let defaults = Self(load: { VoiceSettings() }, save: { _ in })
}

/// Decides when a hands-free turn is over from audio level and transcript
/// stability. Recognition can lag speech, so new text restarts the pause clock.
public struct SpeechEndpoint: Sendable {
    public enum Decision: Equatable, Sendable { case listen, finish, noSpeech }

    private var stopped = false
    private var floor = 0.01
    private var quiet = 0.0
    private var stable = 0.0
    private var elapsed = 0.0
    private var transcript = ""

    public init() {}

    public mutating func receive(level: Double, duration: Double, text: String, mode: SpeechMode) -> Decision {
        guard !stopped, level.isFinite, duration.isFinite, duration > 0 else { return .listen }
        elapsed += duration
        let baseline = floor
        floor = level < baseline ? level : min(0.1, baseline + duration * 0.002)
        quiet = level <= max(0.025, baseline * 1.8) ? quiet + duration : 0
        if text != transcript {
            transcript = text
            stable = 0
            quiet = 0
        } else {
            stable += duration
        }
        if elapsed >= mode.maximumSeconds {
            stopped = true
            return text.isEmpty ? .noSpeech : .finish
        }
        guard let pause = mode.pauseSeconds else { return .listen }
        guard !text.isEmpty else {
            if elapsed >= 8 {
                stopped = true
                return .noSpeech
            }
            return .listen
        }
        if quiet >= pause, stable >= pause {
            stopped = true
            return .finish
        }
        return .listen
    }
}

nonisolated enum SpeechCaptureClientKey: TestDependencyKey {
    static let testValue = SpeechCaptureClient.unavailable
}

nonisolated enum SpeechPlaybackClientKey: TestDependencyKey {
    static let testValue = SpeechPlaybackClient.silent
}

nonisolated enum VoiceSettingsClientKey: DependencyKey {
    static let liveValue = VoiceSettingsClient.userDefaults
    static let testValue = VoiceSettingsClient.defaults
}

extension DependencyValues {
    /// Live value installed by `DevysComposition` from `DevysSpeechLive`.
    public var speechCaptureClient: SpeechCaptureClient {
        get { self[SpeechCaptureClientKey.self] }
        set { self[SpeechCaptureClientKey.self] = newValue }
    }

    public var speechPlaybackClient: SpeechPlaybackClient {
        get { self[SpeechPlaybackClientKey.self] }
        set { self[SpeechPlaybackClientKey.self] = newValue }
    }

    public var voiceSettingsClient: VoiceSettingsClient {
        get { self[VoiceSettingsClientKey.self] }
        set { self[VoiceSettingsClientKey.self] = newValue }
    }
}
