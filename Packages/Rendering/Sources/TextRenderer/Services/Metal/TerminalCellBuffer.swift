import Foundation
import Metal

@MainActor
public final class TerminalCellBuffer {
    private let device: MTLDevice
    private var buffers: [MTLBuffer] = []
    private var bufferRevisions: [Int] = []
    private var currentBufferIndex = 0
    private let bufferCount = 3
    private var capacity: Int
    private var cellData: [TerminalCellGPU]
    private var dirtyRanges: [Range<Int>] = []
    private var requiresFullUpload = false
    private var currentRevision = 0
    private var previousRevision = 0

    public private(set) var cellCount = 0

    public init(device: MTLDevice, initialCapacity: Int = 10_000) {
        self.device = device
        self.capacity = initialCapacity
        self.cellData = []
        self.cellData.reserveCapacity(initialCapacity)
        createBuffers()
    }

    public var currentBuffer: MTLBuffer {
        buffers[currentBufferIndex]
    }

    public func advanceBuffer() {
        currentBufferIndex = (currentBufferIndex + 1) % bufferCount
    }

    public func setCells(
        _ cells: [TerminalCellGPU],
        dirtyRanges: [Range<Int>] = []
    ) {
        previousRevision = currentRevision
        currentRevision &+= 1
        cellData = cells
        cellCount = cells.count
        if cellCount > capacity {
            capacity = max(cellCount * 2, 1)
            createBuffers()
            requiresFullUpload = true
            self.dirtyRanges.removeAll(keepingCapacity: true)
            return
        }

        if dirtyRanges.isEmpty || cellCount == 0 {
            requiresFullUpload = true
            self.dirtyRanges.removeAll(keepingCapacity: true)
            return
        }

        requiresFullUpload = false
        self.dirtyRanges = coalescedDirtyRanges(dirtyRanges, upperBound: cellCount)
    }

    public func syncToGPU() {
        let currentBufferRevision = bufferRevisions[currentBufferIndex]
        let needsUpload = requiresFullUpload
            || !dirtyRanges.isEmpty
            || currentBufferRevision != currentRevision
        guard needsUpload else { return }
        guard cellCount > 0 else {
            requiresFullUpload = false
            dirtyRanges.removeAll(keepingCapacity: true)
            bufferRevisions[currentBufferIndex] = currentRevision
            return
        }

        let requiresRevisionRebase = currentBufferRevision != previousRevision
        let uploadFullFrame = requiresFullUpload
            || dirtyRanges.isEmpty
            || requiresRevisionRebase
        let ranges = uploadFullFrame
            ? [0..<cellCount]
            : dirtyRanges
        let buffer = currentBuffer
        for range in ranges {
            upload(range: range, to: buffer)
        }

        requiresFullUpload = false
        dirtyRanges.removeAll(keepingCapacity: true)
        bufferRevisions[currentBufferIndex] = currentRevision
    }

    private func createBuffers() {
        buffers.removeAll()
        bufferRevisions = Array(repeating: -1, count: bufferCount)
        let bufferSize = capacity * MemoryLayout<TerminalCellGPU>.stride
        for index in 0..<bufferCount {
            guard let buffer = device.makeBuffer(length: bufferSize, options: Self.bufferOptions) else {
                fatalError("TerminalCellBuffer: Failed to create buffer \(index)")
            }
            buffer.label = "TerminalCellBuffer \(index)"
            buffers.append(buffer)
        }
    }

    private static var bufferOptions: MTLResourceOptions {
        #if os(macOS)
        .storageModeManaged
        #else
        .storageModeShared
        #endif
    }

    private func upload(
        range: Range<Int>,
        to buffer: MTLBuffer
    ) {
        guard !range.isEmpty else { return }
        let stride = MemoryLayout<TerminalCellGPU>.stride
        let byteOffset = range.lowerBound * stride
        let byteLength = range.count * stride
        let ptr = buffer.contents()
            .advanced(by: byteOffset)
            .bindMemory(to: TerminalCellGPU.self, capacity: range.count)
        cellData.withUnsafeBufferPointer { src in
            guard let baseAddress = src.baseAddress else { return }
            ptr.update(
                from: baseAddress.advanced(by: range.lowerBound),
                count: range.count
            )
        }

        #if os(macOS)
        buffer.didModifyRange(byteOffset..<byteOffset + byteLength)
        #endif
    }

    private func coalescedDirtyRanges(
        _ dirtyRanges: [Range<Int>],
        upperBound: Int
    ) -> [Range<Int>] {
        let normalizedRanges = dirtyRanges
            .map { max(0, $0.lowerBound)..<min(upperBound, $0.upperBound) }
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                lhs.lowerBound < rhs.lowerBound
            }
        guard let firstRange = normalizedRanges.first else { return [] }

        var coalescedRanges = [firstRange]
        for range in normalizedRanges.dropFirst() {
            guard let lastRange = coalescedRanges.last else {
                coalescedRanges.append(range)
                continue
            }

            if range.lowerBound <= lastRange.upperBound {
                coalescedRanges[coalescedRanges.count - 1] =
                    lastRange.lowerBound..<max(lastRange.upperBound, range.upperBound)
            } else {
                coalescedRanges.append(range)
            }
        }

        return coalescedRanges
    }
}

@MainActor
public final class TerminalOverlayBuffer {
    private let device: MTLDevice
    private var buffer: MTLBuffer?
    private var vertices: [TerminalOverlayVertex] = []
    private var capacity: Int

    public private(set) var vertexCount = 0

    public init(device: MTLDevice, initialCapacity: Int = 1_000) {
        self.device = device
        self.capacity = initialCapacity
        createBuffer()
    }

    public var currentBuffer: MTLBuffer? {
        buffer
    }

    public func clear() {
        vertices.removeAll(keepingCapacity: true)
        vertexCount = 0
    }

    public func addQuad(
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        color: SIMD4<Float>
    ) {
        vertices.append(TerminalOverlayVertex(position: SIMD2(x, y), color: color))
        vertices.append(TerminalOverlayVertex(position: SIMD2(x + width, y), color: color))
        vertices.append(TerminalOverlayVertex(position: SIMD2(x, y + height), color: color))
        vertices.append(TerminalOverlayVertex(position: SIMD2(x + width, y), color: color))
        vertices.append(TerminalOverlayVertex(position: SIMD2(x + width, y + height), color: color))
        vertices.append(TerminalOverlayVertex(position: SIMD2(x, y + height), color: color))
    }

    public func syncToGPU() {
        vertexCount = vertices.count
        guard vertexCount > 0 else { return }

        if vertexCount > capacity {
            capacity = vertexCount * 2
            createBuffer()
        }

        guard let buffer else { return }
        let ptr = buffer.contents().bindMemory(to: TerminalOverlayVertex.self, capacity: capacity)
        vertices.withUnsafeBufferPointer { src in
            if let baseAddress = src.baseAddress {
                ptr.update(from: baseAddress, count: vertexCount)
            }
        }

        #if os(macOS)
        buffer.didModifyRange(0..<vertexCount * MemoryLayout<TerminalOverlayVertex>.stride)
        #endif
    }

    private func createBuffer() {
        let size = capacity * MemoryLayout<TerminalOverlayVertex>.stride
        buffer = device.makeBuffer(length: size, options: Self.bufferOptions)
        buffer?.label = "TerminalOverlayBuffer"
    }

    private static var bufferOptions: MTLResourceOptions {
        #if os(macOS)
        .storageModeManaged
        #else
        .storageModeShared
        #endif
    }
}
