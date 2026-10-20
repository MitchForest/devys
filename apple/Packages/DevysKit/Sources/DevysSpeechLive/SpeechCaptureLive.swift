public import DevysClient
import AVFAudio
import Foundation
import Speech
import os

// Ported from scribble-2's SpeechCaptureEngine: a session id is checked after
// every await, every phase has a deadline, finalization is bounded and falls back
// to the latest heard text, and a dropped audio buffer stops rather than losing
// speech silently. Made cross-platform and locale-aware for Devys.
extension SpeechCaptureClient {
    public static func live() -> Self {
        let engine = SpeechCaptureEngine()
        return Self(
            start: { try await engine.start($0, mode: $1) },
            finish: { try await engine.finish($0) },
            cancel: { await engine.cancel($0) }
        )
    }
}

private actor SpeechCaptureEngine {
    private let logger = Logger(subsystem: "com.mitchwhite.Devys", category: "SpeechCapture")
    private var sessionID: UUID?
    private var analyzer: SpeechAnalyzer?
    private var engine: AVAudioEngine?
    private var hasTap = false
    private var input: AsyncStream<AVReadOnlyAudioPCMBuffer>.Continuation?
    private var events: AsyncThrowingStream<SpeechCaptureEvent, any Error>.Continuation?
    private var stopping: Task<Void, Never>?
    private var preparation: Task<Void, Never>?
    private var processing: Task<Void, Never>?
    private var results: Task<Void, Never>?
    private var interruption: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var reservedLocale: Locale?
    private var finalText = ""
    private var volatileText = ""
    private var failure: SpeechCaptureError?

    private var heardText: String {
        [finalText, volatileText].filter { !$0.isEmpty }.joined(separator: " ")
    }

    func start(_ id: UUID, mode: SpeechMode) async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        if sessionID != nil, let stopping { await stopping.value }
        guard sessionID == nil else { throw SpeechCaptureError.unavailable }
        sessionID = id
        let (stream, sink) = AsyncThrowingStream<SpeechCaptureEvent, any Error>.makeStream()
        events = sink
        sink.onTermination = { @Sendable _ in Task { await self.cancel(id) } }
        armDeadline(id, seconds: 30, error: .unavailable)
        preparation = Task { await self.prepare(id, mode: mode, events: sink) }
        return stream
    }

    private func prepare(_ id: UUID, mode: SpeechMode, events sink: AsyncThrowingStream<SpeechCaptureEvent, any Error>.Continuation) async {
        do {
            sink.yield(.requestingPermission)
            guard await AVAudioApplication.requestRecordPermission() else { throw SpeechCaptureError.microphoneDenied }
            try check(id)
            let authorized = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
            try check(id)
            guard authorized else { throw SpeechCaptureError.speechDenied }
            guard SpeechTranscriber.isAvailable else { throw SpeechCaptureError.unavailable }
            var supported = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
            if supported == nil { supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) }
            guard let locale = supported else { throw SpeechCaptureError.unsupportedLocale }
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: []
            )
            try await installModel(id, locale: locale, transcriber: transcriber, events: sink)
            try check(id)
            sink.yield(.preparing)
            armDeadline(id, seconds: 15, error: .unavailable)
            let converter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber])
            try check(id)
            #if os(iOS)
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
                guard try await session.activate(options: []) else { throw SpeechCaptureError.unavailable }
                try check(id)
            #endif
            let engine = AVAudioEngine()
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechCaptureError.unavailable }
            let (buffers, bufferSink) = AsyncStream<AVReadOnlyAudioPCMBuffer>.makeStream(bufferingPolicy: .bufferingNewest(64))
            let (inputs, inputSink) = AsyncStream<AnalyzerInput>.makeStream()
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try engine.inputNode.installAudioTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                if case .dropped = bufferSink.yield(AVReadOnlyAudioPCMBuffer(copying: AVAudioPCMBuffer(copying: buffer))) {
                    Task { await self.stop(id, error: .unavailable) }
                }
            }
            hasTap = true
            self.engine = engine
            self.analyzer = analyzer
            input = bufferSink
            finalText = ""
            volatileText = ""
            failure = nil
            let context = ProcessingContext(converter: converter, inputs: inputSink, sampleRate: format.sampleRate, id: id, mode: mode, events: sink)
            processing = Task { await self.process(buffers, context) }
            results = Task {
                do {
                    for try await result in transcriber.results {
                        guard self.sessionID == id else { return }
                        self.receive(String(result.text.characters), isFinal: result.isFinal)
                        sink.yield(.transcript(finalized: self.finalText, volatile: self.volatileText))
                    }
                } catch {
                    guard self.sessionID == id, !Task.isCancelled else { return }
                    self.failure = .unavailable
                    sink.finish(throwing: SpeechCaptureError.unavailable)
                }
            }
            #if os(iOS)
                interruption = Task {
                    for await _ in NotificationCenter.default.notifications(named: AVAudioSession.didBecomeInactiveNotification) {
                        await self.stop(id, error: .interrupted)
                        return
                    }
                }
            #endif
            engine.prepare()
            try await analyzer.start(inputSequence: inputs)
            try check(id)
            try engine.start()
            armDeadline(id, seconds: mode.maximumSeconds + 5, error: .timeLimit)
            logger.info("Microphone capture started")
            sink.yield(.listening)
        } catch {
            await stop(id, error: error as? SpeechCaptureError ?? .unavailable)
        }
    }

    private func receive(_ text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            finalText = [finalText, trimmed].filter { !$0.isEmpty }.joined(separator: " ")
            volatileText = ""
        } else {
            volatileText = trimmed
        }
    }

    private struct ProcessingContext {
        let converter: AnalyzerInputConverter
        let inputs: AsyncStream<AnalyzerInput>.Continuation
        let sampleRate: Double
        let id: UUID
        let mode: SpeechMode
        let events: AsyncThrowingStream<SpeechCaptureEvent, any Error>.Continuation
    }

    private func process(_ buffers: AsyncStream<AVReadOnlyAudioPCMBuffer>, _ context: ProcessingContext) async {
        let (converter, inputs, sampleRate, id, mode, sink) = (context.converter, context.inputs, context.sampleRate, context.id, context.mode, context.events)
        var endpoint = SpeechEndpoint()
        var levelElapsed = 0.0
        do {
            for await buffer in buffers {
                guard sessionID == id, !Task.isCancelled else { break }
                for converted in try converter.convert(AVAudioPCMBuffer(copying: buffer), at: nil) { inputs.yield(converted) }
                let seconds = Double(buffer.frameLength) / sampleRate
                let level = Self.level(buffer)
                levelElapsed += seconds
                if levelElapsed >= 0.1 {
                    sink.yield(.level(min(1, level * 8)))
                    levelElapsed = 0
                }
                switch endpoint.receive(level: level, duration: seconds, text: heardText, mode: mode) {
                case .listen: break
                case .finish:
                    stopInput()
                    sink.yield(.endOfSpeech)
                case .noSpeech:
                    await stop(id, error: .noSpeech)
                }
            }
            if sessionID == id, !Task.isCancelled {
                for converted in try converter.flush() { inputs.yield(converted) }
            }
        } catch {
            if sessionID == id, !Task.isCancelled {
                failure = .unavailable
                sink.finish(throwing: SpeechCaptureError.unavailable)
            }
        }
        inputs.finish()
    }

    private func installModel(
        _ id: UUID,
        locale: Locale,
        transcriber: SpeechTranscriber,
        events sink: AsyncThrowingStream<SpeechCaptureEvent, any Error>.Continuation
    ) async throws {
        do {
            if try await AssetInventory.reserve(locale: locale) { reservedLocale = locale }
            try check(id)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try check(id)
                sink.yield(.downloadingModel)
                armDeadline(id, seconds: 180, error: .modelUnavailable)
                try await request.downloadAndInstall()
            }
        } catch {
            try check(id)
            throw SpeechCaptureError.modelUnavailable
        }
    }

    func finish(_ id: UUID) async throws -> String {
        try check(id)
        guard let analyzer else { throw SpeechCaptureError.unavailable }
        stopInput()
        deadline?.cancel()
        let gate = FinishGate()
        let resultsTask = results
        let processingTask = processing
        let work = Task {
            await processingTask?.value
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                await resultsTask?.value
                await gate.resolve(true)
            } catch {
                await gate.resolve(false)
            }
        }
        // Finalization can wedge; keep what was heard after five seconds.
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            await gate.resolve(false)
        }
        let finished = await gate.wait()
        work.cancel()
        timeout.cancel()
        let settled = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = settled.isEmpty ? heardText.trimmingCharacters(in: .whitespacesAndNewlines) : settled
        let error = failure ?? (finished ? .noSpeech : .unavailable)
        let valid = failure == nil && sessionID == id && !text.isEmpty
        await cancel(id)
        guard valid else { throw error }
        return text
    }

    func cancel(_ id: UUID) async {
        await stop(id, error: .cancelled)
    }

    private func stop(_ id: UUID, error: SpeechCaptureError) async {
        guard sessionID == id else { return }
        if let stopping {
            await stopping.value
            return
        }
        failure = error
        stopInput()
        preparation?.cancel()
        preparation = nil
        processing?.cancel()
        results?.cancel()
        interruption?.cancel()
        deadline?.cancel()
        events?.finish(throwing: error)
        events = nil
        let analyzer = self.analyzer
        self.analyzer = nil
        let reserved = reservedLocale
        reservedLocale = nil
        let stopping = Task {
            let gate = FinishGate()
            let cleanup = Task {
                await analyzer?.cancelAndFinishNow()
                if let reserved { _ = await AssetInventory.release(reservedLocale: reserved) }
                await gate.resolve(true)
            }
            let timeout = Task {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                await gate.resolve(false)
            }
            _ = await gate.wait()
            cleanup.cancel()
            timeout.cancel()
            await self.clear(id)
        }
        self.stopping = stopping
        await stopping.value
    }

    private func clear(_ id: UUID) {
        guard sessionID == id else { return }
        engine = nil
        sessionID = nil
        stopping = nil
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        #endif
    }

    private func armDeadline(_ id: UUID, seconds: Double, error: SpeechCaptureError) {
        deadline?.cancel()
        deadline = Task {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            await self.stop(id, error: error)
        }
    }

    private static func level(_ buffer: AVReadOnlyAudioPCMBuffer) -> Double {
        guard buffer.frameLength > 0, case .float(let samples) = buffer.channelData(0) else { return 0 }
        var sum = 0.0
        for index in 0..<buffer.frameLength { sum += Double(samples[index] * samples[index]) }
        return sqrt(sum / Double(buffer.frameLength))
    }

    private func check(_ id: UUID) throws {
        guard sessionID == id, !Task.isCancelled else { throw SpeechCaptureError.cancelled }
    }

    private func stopInput() {
        if let engine {
            if hasTap {
                engine.inputNode.removeTap(onBus: 0)
                hasTap = false
            }
            engine.stop()
        }
        input?.finish()
        input = nil
    }
}

private actor FinishGate {
    private var value: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?

    func resolve(_ value: Bool) {
        guard self.value == nil else { return }
        self.value = value
        continuation?.resume(returning: value)
        continuation = nil
    }

    func wait() async -> Bool {
        if let value { return value }
        return await withCheckedContinuation { continuation = $0 }
    }
}
