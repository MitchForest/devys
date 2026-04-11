import AVFoundation
import AppKit
import Foundation
import Speech

struct AgentComposerSpeechEvent: Sendable, Equatable {
    var text: String
    var isFinal: Bool
}

enum AgentComposerSpeechError: Error, Equatable {
    case permissionDenied(String)
    case unavailable(String)
    case failed(String)
}

@MainActor
protocol AgentComposerSpeechCapture: AnyObject {
    func stop() async
}

@MainActor
protocol AgentComposerSpeechService: Sendable {
    func startTranscription(
        onEvent: @escaping @MainActor @Sendable (AgentComposerSpeechEvent) -> Void
    ) async throws -> any AgentComposerSpeechCapture
}

struct DefaultAgentComposerSpeechService: AgentComposerSpeechService {
    func startTranscription(
        onEvent: @escaping @MainActor @Sendable (AgentComposerSpeechEvent) -> Void
    ) async throws -> any AgentComposerSpeechCapture {
        guard #available(macOS 26.0, *) else {
            throw AgentComposerSpeechError.unavailable(
                "Speech input requires macOS 26 or newer."
            )
        }

        try await requestSpeechAuthorization()
        try await requestMicrophoneAuthorization()
        return try await AppleSpeechAnalyzerCapture.start(onEvent: onEvent)
    }

    private func requestSpeechAuthorization() async throws {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        let status: SFSpeechRecognizerAuthorizationStatus
        if currentStatus == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { authorizationStatus in
                    continuation.resume(returning: authorizationStatus)
                }
            }
        } else {
            status = currentStatus
        }

        guard status == .authorized else {
            throw AgentComposerSpeechError.permissionDenied(
                "Speech recognition permission was denied."
            )
        }
    }

    private func requestMicrophoneAuthorization() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let isAuthorized: Bool
        switch status {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            isAuthorized = false
        }

        guard isAuthorized else {
            throw AgentComposerSpeechError.permissionDenied(
                "Microphone permission was denied."
            )
        }
    }
}

@available(macOS 26.0, *)
@MainActor
private final class AppleSpeechAnalyzerCapture: AgentComposerSpeechCapture {
    private let engine = AVAudioEngine()
    private let analyzer: SpeechAnalyzer
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let analyzerTask: Task<Void, Never>
    private let resultsTask: Task<Void, Never>

    private init(
        analyzer: SpeechAnalyzer,
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        analyzerTask: Task<Void, Never>,
        resultsTask: Task<Void, Never>
    ) {
        self.analyzer = analyzer
        self.continuation = continuation
        self.analyzerTask = analyzerTask
        self.resultsTask = resultsTask
    }

    static func start(
        onEvent: @escaping @MainActor @Sendable (AgentComposerSpeechEvent) -> Void
    ) async throws -> AppleSpeechAnalyzerCapture {
        let locale = Locale.autoupdatingCurrent

        if SpeechTranscriber.isAvailable,
           let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = SpeechTranscriber(
                locale: resolvedLocale,
                preset: .progressiveTranscription
            )
            return try await start(speechModule: transcriber) {
                for try await result in transcriber.results {
                    await onEvent(
                        AgentComposerSpeechEvent(
                            text: String(result.text.characters),
                            isFinal: result.isFinal
                        )
                    )
                }
            }
        }

        if let resolvedLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = DictationTranscriber(
                locale: resolvedLocale,
                preset: .progressiveLongDictation
            )
            return try await start(speechModule: transcriber) {
                for try await result in transcriber.results {
                    await onEvent(
                        AgentComposerSpeechEvent(
                            text: String(result.text.characters),
                            isFinal: result.isFinal
                        )
                    )
                }
            }
        }

        throw AgentComposerSpeechError.unavailable(
            "No Apple speech transcriber is available for the current locale."
        )
    }

    static func start(
        speechModule: any SpeechModule,
        consumeResults: @escaping @Sendable () async throws -> Void
    ) async throws -> AppleSpeechAnalyzerCapture {
        let (stream, continuation) = makeInputStream()
        let analyzer = SpeechAnalyzer(modules: [speechModule])
        let capture = AppleSpeechAnalyzerCapture(
            analyzer: analyzer,
            continuation: continuation,
            analyzerTask: Task {},
            resultsTask: Task {}
        )

        try await capture.configureAudioInput()

        let analyzerTask = Task {
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                await MainActor.run {
                    NSSound.beep()
                }
            }
        }

        let resultsTask = Task {
            do {
                try await consumeResults()
            } catch {
                await MainActor.run {
                    NSSound.beep()
                }
            }
        }

        return AppleSpeechAnalyzerCapture(
            analyzer: analyzer,
            continuation: continuation,
            analyzerTask: analyzerTask,
            resultsTask: resultsTask
        )
    }

    func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
        resultsTask.cancel()
        analyzerTask.cancel()
        await analyzer.cancelAndFinishNow()
    }

    private func configureAudioInput() async throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        try await analyzer.prepareToAnalyze(in: inputFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [continuation] buffer, _ in
            continuation.yield(AnalyzerInput(buffer: buffer))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw AgentComposerSpeechError.failed(
                "Failed to start microphone capture: \(error.localizedDescription)"
            )
        }
    }
}

@available(macOS 26.0, *)
private func makeInputStream() -> (AsyncStream<AnalyzerInput>, AsyncStream<AnalyzerInput>.Continuation) {
    var capturedContinuation: AsyncStream<AnalyzerInput>.Continuation?
    let stream = AsyncStream<AnalyzerInput> { continuation in
        capturedContinuation = continuation
    }

    guard let continuation = capturedContinuation else {
        preconditionFailure("Failed to create analyzer input continuation.")
    }

    return (stream, continuation)
}
