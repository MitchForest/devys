import Foundation
import AVFoundation
import AppKit
import Speech

public struct TerminalComposerSpeechEvent: Equatable, Sendable {
    public var text: String
    public var isFinal: Bool
    public var audioLevel: Double

    public init(text: String, isFinal: Bool, audioLevel: Double = 0) {
        self.text = text
        self.isFinal = isFinal
        self.audioLevel = min(max(audioLevel, 0), 1)
    }
}

public enum TerminalComposerSpeechError: Error, Equatable, Sendable {
    case permissionDenied(String)
    case unavailable(String)
    case failed(String)
}

@MainActor
public protocol TerminalComposerSpeechCapture: AnyObject {
    func stop() async
}

@MainActor
public protocol TerminalComposerSpeechService: Sendable {
    func startTranscription(
        onEvent: @escaping @MainActor @Sendable (TerminalComposerSpeechEvent) -> Void
    ) async throws -> any TerminalComposerSpeechCapture
}

public struct DefaultTerminalComposerSpeechService: TerminalComposerSpeechService {
    public init() {}

    public func startTranscription(
        onEvent: @escaping @MainActor @Sendable (TerminalComposerSpeechEvent) -> Void
    ) async throws -> any TerminalComposerSpeechCapture {
        try await requestSpeechAuthorization()
        try await requestMicrophoneAuthorization()
        return try await AppleTerminalComposerSpeechCapture.start(onEvent: onEvent)
    }

    private func requestSpeechAuthorization() async throws {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        let status: SFSpeechRecognizerAuthorizationStatus
        if currentStatus == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { @Sendable authorizationStatus in
                    continuation.resume(returning: authorizationStatus)
                }
            }
        } else {
            status = currentStatus
        }

        guard status == .authorized else {
            throw TerminalComposerSpeechError.permissionDenied("Speech recognition permission was denied.")
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
            throw TerminalComposerSpeechError.permissionDenied("Microphone permission was denied.")
        }
    }
}

@MainActor
private final class AppleTerminalComposerSpeechCapture: TerminalComposerSpeechCapture {
    private let engine = AVAudioEngine()
    private let analyzer: SpeechAnalyzer
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var analyzerTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var latestAudioLevel = AudioLevelBox()

    private init(
        analyzer: SpeechAnalyzer,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) {
        self.analyzer = analyzer
        self.continuation = continuation
    }

    static func start(
        onEvent: @escaping @MainActor @Sendable (TerminalComposerSpeechEvent) -> Void
    ) async throws -> AppleTerminalComposerSpeechCapture {
        let locale = Locale.autoupdatingCurrent

        if SpeechTranscriber.isAvailable,
           let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = SpeechTranscriber(locale: resolvedLocale, preset: .progressiveTranscription)
            try await ensureAssets(for: transcriber)
            return try await start(speechModule: transcriber, onEvent: onEvent) { latestAudioLevel in
                for try await result in transcriber.results {
                    await onEvent(
                        TerminalComposerSpeechEvent(
                            text: String(result.text.characters),
                            isFinal: result.isFinal,
                            audioLevel: await latestAudioLevel.value
                        )
                    )
                }
            }
        }

        if let resolvedLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = DictationTranscriber(locale: resolvedLocale, preset: .progressiveLongDictation)
            try await ensureAssets(for: transcriber)
            return try await start(speechModule: transcriber, onEvent: onEvent) { latestAudioLevel in
                for try await result in transcriber.results {
                    await onEvent(
                        TerminalComposerSpeechEvent(
                            text: String(result.text.characters),
                            isFinal: result.isFinal,
                            audioLevel: await latestAudioLevel.value
                        )
                    )
                }
            }
        }

        throw TerminalComposerSpeechError.unavailable(
            "No Apple speech transcriber is available for the current locale."
        )
    }

    private static func ensureAssets(for speechModule: any SpeechModule) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [speechModule]) {
            try await request.downloadAndInstall()
        }
    }

    private static func start(
        speechModule: any SpeechModule,
        onEvent: @escaping @MainActor @Sendable (TerminalComposerSpeechEvent) -> Void,
        consumeResults: @escaping @Sendable (_ latestAudioLevel: AudioLevelBox) async throws -> Void
    ) async throws -> AppleTerminalComposerSpeechCapture {
        let (stream, continuation) = makeAnalyzerInputStream()
        let analyzer = SpeechAnalyzer(modules: [speechModule])
        let capture = AppleTerminalComposerSpeechCapture(
            analyzer: analyzer,
            continuation: continuation
        )

        try await capture.configureAudioInput(compatibleWith: speechModule) { audioLevel in
            onEvent(TerminalComposerSpeechEvent(text: "", isFinal: false, audioLevel: audioLevel))
        }

        capture.analyzerTask = Task {
            do {
                let lastSampleTime = try await analyzer.analyzeSequence(stream)
                if let lastSampleTime {
                    try await analyzer.finalizeAndFinish(through: lastSampleTime)
                } else {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    NSSound.beep()
                }
            }
        }

        let latestAudioLevel = capture.latestAudioLevel
        capture.resultsTask = Task {
            do {
                try await consumeResults(latestAudioLevel)
            } catch {
                await MainActor.run {
                    NSSound.beep()
                }
            }
        }

        do {
            try capture.startAudioInput()
        } catch {
            await capture.stop()
            throw error
        }

        return capture
    }

    func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
        await analyzerTask?.value
        await resultsTask?.value
        analyzerTask = nil
        resultsTask = nil
    }

    private func configureAudioInput(
        compatibleWith speechModule: any SpeechModule,
        onAudioLevel: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [speechModule],
            considering: inputFormat
        )

        guard let analyzerFormat else {
            throw TerminalComposerSpeechError.unavailable(
                "No compatible Apple speech audio format is available."
            )
        }

        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let latestAudioLevel = latestAudioLevel
        let inputConverter = AnalyzerAudioInputConverter(
            inputFormat: inputFormat,
            analyzerFormat: analyzerFormat
        )
        Self.installAudioTap(
            on: inputNode,
            inputFormat: inputFormat,
            continuation: continuation,
            inputConverter: inputConverter,
            latestAudioLevel: latestAudioLevel,
            onAudioLevel: onAudioLevel
        )

        engine.prepare()
    }

    nonisolated private static func installAudioTap(
        on inputNode: AVAudioInputNode,
        inputFormat: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation,
        inputConverter: AnalyzerAudioInputConverter,
        latestAudioLevel: AudioLevelBox,
        onAudioLevel: @escaping @MainActor @Sendable (Double) -> Void
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            guard let analyzerBuffer = inputConverter.convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: analyzerBuffer))
            let level = Self.audioLevel(from: buffer)
            Task {
                await latestAudioLevel.update(level)
            }
            Task { @MainActor in
                onAudioLevel(level)
            }
        }
    }

    private func startAudioInput() throws {
        do {
            try engine.start()
        } catch {
            throw TerminalComposerSpeechError.failed(
                "Failed to start microphone capture: \(error.localizedDescription)"
            )
        }
    }

    nonisolated private static func audioLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData,
              buffer.frameLength > 0
        else { return 0 }

        let channel = channelData[0]
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0
        for frame in 0..<frameCount {
            let sample = channel[frame]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        return min(max(Double(rms) * 12, 0), 1)
    }
}

private final class AnalyzerAudioInputConverter {
    private let analyzerFormat: AVAudioFormat
    private let converter: AVAudioConverter?

    init(inputFormat: AVAudioFormat, analyzerFormat: AVAudioFormat) {
        self.analyzerFormat = analyzerFormat
        if inputFormat.isEquivalent(to: analyzerFormat) {
            self.converter = nil
        } else {
            self.converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
        }
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }

        let sampleRateRatio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio) + 1
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: analyzerFormat,
            frameCapacity: frameCapacity
        ) else { return nil }

        let inputProvider = AnalyzerAudioInputProvider(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.provide(inputStatus: inputStatus)
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            break
        case .error:
            return nil
        @unknown default:
            return nil
        }
        guard convertedBuffer.frameLength > 0 else { return nil }

        return convertedBuffer
    }
}

// AVAudioConverter invokes this provider synchronously during `convert`.
// The tap-owned buffer never outlives that conversion call.
private final class AnalyzerAudioInputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func provide(inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if didProvideInput {
            inputStatus.pointee = .noDataNow
            return nil
        }
        didProvideInput = true
        inputStatus.pointee = .haveData
        return buffer
    }
}

private extension AVAudioFormat {
    func isEquivalent(to other: AVAudioFormat) -> Bool {
        sampleRate == other.sampleRate
            && channelCount == other.channelCount
            && commonFormat == other.commonFormat
            && isInterleaved == other.isInterleaved
    }
}

private actor AudioLevelBox {
    var value: Double = 0

    func update(_ newValue: Double) {
        value = newValue
    }
}

private func makeAnalyzerInputStream() -> (AsyncStream<AnalyzerInput>, AsyncStream<AnalyzerInput>.Continuation) {
    AsyncStream.makeStream(of: AnalyzerInput.self, bufferingPolicy: .bufferingNewest(16))
}
