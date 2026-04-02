// VideoScene.swift
// MetalASCII - Video-to-ASCII real-time conversion
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import AVFoundation
import CoreImage
import Metal

// MARK: - Video Scene

/// ASCII art scene that converts video frames to ASCII in real-time.
///
/// Features:
/// - Real-time video frame extraction via AVFoundation
/// - Synchronized playback at video's native FPS
/// - Shape-aware ASCII conversion for best quality
/// - Looping playback support
public final class VideoScene: ASCIIScene, @unchecked Sendable {

    public let name = "Video"
    public let description = "Real-time video to ASCII conversion"

    // MARK: - Configuration

    /// Path to the video file
    public var videoURL: URL? {
        didSet {
            if videoURL != oldValue {
                loadVideo()
            }
        }
    }

    /// Whether to loop the video
    public var loop: Bool = true

    /// Playback speed multiplier
    public var playbackSpeed: Float = 1.0

    /// Number of ASCII columns
    public var columns: Int = 120

    /// Invert brightness
    public var invertBrightness: Bool = false

    /// Animation intensity for effects
    public var animationIntensity: Float = 0.0

    // MARK: - State

    public enum PlaybackState: String {
        case idle = "Idle"
        case loading = "Loading"
        case playing = "Playing"
        case paused = "Paused"
        case finished = "Finished"
        case error = "Error"
    }

    public private(set) var playbackState: PlaybackState = .idle
    public private(set) var currentTime: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var videoFPS: Double = 30
    public private(set) var errorMessage: String?

    private var time: Float = 0
    private var viewportSize: CGSize = .zero
    private var lastFrameTime: Double = 0
    private var frameInterval: Double = 1.0 / 30.0

    // MARK: - Output

    public private(set) var asciiOutput: [[Character]] = []
    public private(set) var brightnessOutput: [[Float]] = []

    // MARK: - Video Processing

    private var asset: AVAsset?
    private var assetReader: AVAssetReader?
    private var videoOutput: AVAssetReaderTrackOutput?
    private var videoTrack: AVAssetTrack?
    private var ciContext: CIContext?

    // Frame buffer for smooth playback
    private var frameBuffer: [FrameData] = []
    private var currentFrameIndex: Int = 0
    private let maxBufferedFrames = 60

    private struct FrameData {
        let timestamp: Double
        let ascii: [[Character]]
        let brightness: [[Float]]
    }

    // MARK: - Metal

    private let device: MTLDevice

    // MARK: - Generator

    private let generator = ShapeAwareASCIIGenerator()

    // MARK: - Initialization

    public required init(device: MTLDevice) throws {
        self.device = device
        self.ciContext = CIContext(mtlDevice: device)

        generator.contrastBoost = 1.2
        generator.gamma = 0.95

        resize(to: CGSize(width: 1200, height: 800))
    }

    // MARK: - Video Loading

    private func loadVideo() {
        guard let url = videoURL else {
            playbackState = .idle
            return
        }

        playbackState = .loading
        errorMessage = nil
        frameBuffer.removeAll()
        currentFrameIndex = 0
        currentTime = 0

        // Load asset
        asset = AVAsset(url: url)

        Task { [weak self] in
            guard let self, let asset = self.asset else { return }

            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else {
                    playbackState = .error
                    errorMessage = "No video track found"
                    return
                }

                let durationTime = try await asset.load(.duration)
                let nominalFrameRate = try await track.load(.nominalFrameRate)

                videoTrack = track
                duration = CMTimeGetSeconds(durationTime)
                videoFPS = nominalFrameRate > 0 ? Double(nominalFrameRate) : 30
                frameInterval = 1.0 / videoFPS

                // Start reading frames
                startReading()
            } catch {
                playbackState = .error
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startReading() {
        guard let asset = asset, let track = videoTrack else { return }

        do {
            assetReader = try AVAssetReader(asset: asset)

            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            videoOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)

            if let output = videoOutput, assetReader?.canAdd(output) == true {
                assetReader?.add(output)
            }

            assetReader?.startReading()
            playbackState = .playing

            // Pre-buffer some frames
            prebufferFrames()

        } catch {
            playbackState = .error
            errorMessage = error.localizedDescription
        }
    }

    private func prebufferFrames() {
        // Buffer frames on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var bufferedCount = 0
            while bufferedCount < self.maxBufferedFrames {
                if let frameData = self.readNextFrame() {
                    DispatchQueue.main.async {
                        self.frameBuffer.append(frameData)
                    }
                    bufferedCount += 1
                } else {
                    break
                }
            }
        }
    }

    private func readNextFrame() -> FrameData? {
        guard let output = videoOutput,
              let sampleBuffer = output.copyNextSampleBuffer() else {
            return nil
        }

        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        // Convert to NSImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        guard let cgImage = ciContext?.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        // Convert to ASCII
        generator.invertBrightness = invertBrightness
        let text = generator.convert(image: nsImage, columns: columns)

        // Parse into arrays
        let (ascii, brightness) = parseASCIIText(text)

        return FrameData(timestamp: timestamp, ascii: ascii, brightness: brightness)
    }

    private func parseASCIIText(_ text: String) -> ([[Character]], [[Float]]) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        var asciiOutput: [[Character]] = []
        var brightnessOutput: [[Float]] = []

        let ramp = ASCIICharacterRamp.standard
        let rampCount = ramp.count

        for line in lines {
            var charRow: [Character] = []
            var brightRow: [Float] = []

            for char in line {
                charRow.append(char)

                if let index = ramp.firstIndex(of: char) {
                    let brightness = Float(ramp.distance(from: ramp.startIndex, to: index)) / Float(rampCount - 1)
                    brightRow.append(brightness)
                } else {
                    brightRow.append(0)
                }
            }

            asciiOutput.append(charRow)
            brightnessOutput.append(brightRow)
        }

        return (asciiOutput, brightnessOutput)
    }

    // MARK: - Playback Control

    public func play() {
        if playbackState == .paused {
            playbackState = .playing
        } else if playbackState == .finished && loop {
            restart()
        }
    }

    public func pause() {
        if playbackState == .playing {
            playbackState = .paused
        }
    }

    public func togglePlayPause() {
        if playbackState == .playing {
            pause()
        } else {
            play()
        }
    }

    public func restart() {
        frameBuffer.removeAll()
        currentFrameIndex = 0
        currentTime = 0

        // Reset reader
        assetReader?.cancelReading()
        startReading()
    }

    // MARK: - ASCIIScene Protocol

    public func resize(to size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        viewportSize = size

        // Adjust columns based on viewport
        let maxColumns = Int(size.width / 8)
        if columns > maxColumns {
            columns = maxColumns
        }
    }

    public func update(deltaTime: Float) {
        time += deltaTime

        guard playbackState == .playing else { return }

        // Advance time
        currentTime += Double(deltaTime) * Double(playbackSpeed)

        // Find the right frame for current time
        while currentFrameIndex < frameBuffer.count {
            let frame = frameBuffer[currentFrameIndex]

            if frame.timestamp <= currentTime {
                // Use this frame
                asciiOutput = frame.ascii
                brightnessOutput = frame.brightness
                currentFrameIndex += 1
            } else {
                break
            }
        }

        // Check if we need more frames
        if currentFrameIndex >= frameBuffer.count - 10 {
            bufferMoreFrames()
        }

        // Check for end of video
        if currentTime >= duration {
            if loop {
                restart()
            } else {
                playbackState = .finished
            }
        }

        // Apply animation effects if enabled
        if animationIntensity > 0 {
            applyAnimationEffects()
        }
    }

    private func bufferMoreFrames() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var count = 0
            while count < 10 {
                if let frameData = self.readNextFrame() {
                    DispatchQueue.main.async {
                        self.frameBuffer.append(frameData)
                    }
                    count += 1
                } else {
                    break
                }
            }
        }
    }

    public func render(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor) {
        // CPU-based rendering, just clear the pass
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.endEncoding()
        }
    }

    // MARK: - Animation Effects

    private func applyAnimationEffects() {
        guard !brightnessOutput.isEmpty else { return }

        let rows = brightnessOutput.count
        guard rows > 0 else { return }

        // Subtle scanline effect
        let scanlineY = Int(time * 40) % rows

        for row in 0..<rows {
            for col in 0..<brightnessOutput[row].count {
                var brightness = brightnessOutput[row][col]

                // Scanline
                if row == scanlineY {
                    brightness += 0.15 * animationIntensity
                }

                // CRT glow simulation
                let glow = sin(time * 5.0) * 0.03 * animationIntensity
                brightness += glow

                brightnessOutput[row][col] = max(0, min(1, brightness))
            }
        }
    }

    /// Get current frame as ASCII string
    public func getASCIIString() -> String {
        return asciiOutput.map { String($0) }.joined(separator: "\n")
    }

    /// Get progress as percentage (0-1)
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    /// Format time as MM:SS
    public var formattedTime: String {
        let current = Int(currentTime)
        let total = Int(duration)
        return String(format: "%d:%02d / %d:%02d", current / 60, current % 60, total / 60, total % 60)
    }
}

#endif // os(macOS)
