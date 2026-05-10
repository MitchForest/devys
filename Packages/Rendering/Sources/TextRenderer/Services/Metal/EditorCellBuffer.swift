// EditorCellBuffer.swift
// DevysTextRenderer - Shared Metal text rendering
//
// GPU buffer for editor cell data.

import Foundation
import Metal

// MARK: - Cell Buffer

/// Manages a Metal buffer containing cell data for GPU rendering.
/// Uses triple-buffering for CPU/GPU synchronization.
@MainActor
public final class EditorCellBuffer {
    
    // MARK: - Properties
    
    private let device: MTLDevice
    
    /// Triple-buffered cell data
    private var buffers: [MTLBuffer] = []
    
    /// Current buffer index
    private var currentBufferIndex: Int = 0
    
    /// Number of buffers
    private let bufferCount: Int = 3
    
    /// Maximum cells capacity
    private var capacity: Int
    
    /// Current cell count
    public private(set) var cellCount: Int = 0
    
    /// CPU-side cell data
    private var cellData: [EditorCellGPU]
    
    /// Whether buffer needs sync
    private var isDirty: Bool = false
    
    // MARK: - Initialization
    
    /// Create cell buffer with initial capacity
    public init(device: MTLDevice, initialCapacity: Int = 10000) {
        self.device = device
        self.capacity = initialCapacity
        self.cellData = []
        self.cellData.reserveCapacity(initialCapacity)
        
        createBuffers()
    }
    
    // MARK: - Buffer Management
    
    private func createBuffers() {
        buffers.removeAll()
        
        let bufferSize = capacity * MemoryLayout<EditorCellGPU>.stride
        
        for i in 0..<bufferCount {
            guard let buffer = device.makeBuffer(
                length: bufferSize,
                options: Self.bufferOptions
            ) else {
                fatalError("EditorCellBuffer: Failed to create buffer \(i)")
            }
            buffer.label = "EditorCellBuffer \(i)"
            buffers.append(buffer)
        }
    }
    
    /// Get current buffer for rendering
    public var currentBuffer: MTLBuffer {
        buffers[currentBufferIndex]
    }
    
    /// Advance to next buffer
    public func advanceBuffer() {
        currentBufferIndex = (currentBufferIndex + 1) % bufferCount
    }
    
    // MARK: - Cell Updates
    
    /// Clear all cells
    public func clear() {
        cellData.removeAll(keepingCapacity: true)
        cellCount = 0
        isDirty = true
    }
    
    /// Begin building cells for a frame
    public func beginFrame() {
        cellData.removeAll(keepingCapacity: true)
    }
    
    /// Add a cell
    public func addCell(_ cell: EditorCellGPU) {
        cellData.append(cell)
    }
    
    /// Add multiple cells
    public func addCells(_ cells: [EditorCellGPU]) {
        cellData.append(contentsOf: cells)
    }
    
    /// End building and prepare for rendering
    public func endFrame() {
        cellCount = cellData.count
        
        // Grow buffer if needed
        if cellCount > capacity {
            capacity = cellCount * 2
            createBuffers()
        }
        
        isDirty = true
    }
    
    /// Sync to GPU (call before rendering)
    public func syncToGPU() {
        guard isDirty, cellCount > 0 else { return }
        
        // Sync to all buffers for triple buffering
        for buffer in buffers {
            let ptr = buffer.contents().bindMemory(to: EditorCellGPU.self, capacity: capacity)
            cellData.withUnsafeBufferPointer { srcPtr in
                if let baseAddress = srcPtr.baseAddress {
                    ptr.update(from: baseAddress, count: cellCount)
                }
            }
            
            #if os(macOS)
            buffer.didModifyRange(0..<cellCount * MemoryLayout<EditorCellGPU>.stride)
            #endif
        }
        
        isDirty = false
    }
    
    // MARK: - Statistics
    
    public var bufferSize: Int {
        capacity * MemoryLayout<EditorCellGPU>.stride
    }

    private static var bufferOptions: MTLResourceOptions {
        #if os(macOS)
        .storageModeManaged
        #else
        .storageModeShared
        #endif
    }
}

// MARK: - Overlay Buffer

/// Buffer for overlay vertices (cursor, selection)
@MainActor
public final class EditorOverlayBuffer {
    
    private let device: MTLDevice
    private var buffer: MTLBuffer?
    private var vertices: [EditorOverlayVertex] = []
    private var capacity: Int
    
    public private(set) var vertexCount: Int = 0
    
    public init(device: MTLDevice, initialCapacity: Int = 1000) {
        self.device = device
        self.capacity = initialCapacity
        createBuffer()
    }
    
    private func createBuffer() {
        let size = capacity * MemoryLayout<EditorOverlayVertex>.stride
        buffer = device.makeBuffer(length: size, options: Self.bufferOptions)
        buffer?.label = "EditorOverlayBuffer"
    }
    
    public var currentBuffer: MTLBuffer? { buffer }
    
    public func clear() {
        vertices.removeAll(keepingCapacity: true)
        vertexCount = 0
    }
    
    /// Add a quad (6 vertices for 2 triangles)
    public func addQuad(
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        color: SIMD4<Float>
    ) {
        // Triangle 1
        vertices.append(EditorOverlayVertex(position: SIMD2(x, y), color: color))
        vertices.append(EditorOverlayVertex(position: SIMD2(x + width, y), color: color))
        vertices.append(EditorOverlayVertex(position: SIMD2(x, y + height), color: color))
        
        // Triangle 2
        vertices.append(EditorOverlayVertex(position: SIMD2(x + width, y), color: color))
        vertices.append(EditorOverlayVertex(position: SIMD2(x + width, y + height), color: color))
        vertices.append(EditorOverlayVertex(position: SIMD2(x, y + height), color: color))
    }
    
    public func syncToGPU() {
        vertexCount = vertices.count
        guard vertexCount > 0, buffer != nil else { return }
        
        if vertexCount > capacity {
            capacity = vertexCount * 2
            createBuffer()
        }
        
        guard let buf = self.buffer else { return }
        
        let ptr = buf.contents().bindMemory(to: EditorOverlayVertex.self, capacity: capacity)
        vertices.withUnsafeBufferPointer { srcPtr in
            if let baseAddress = srcPtr.baseAddress {
                ptr.update(from: baseAddress, count: vertexCount)
            }
        }
        
        #if os(macOS)
        buf.didModifyRange(0..<vertexCount * MemoryLayout<EditorOverlayVertex>.stride)
        #endif
    }

    private static var bufferOptions: MTLResourceOptions {
        #if os(macOS)
        .storageModeManaged
        #else
        .storageModeShared
        #endif
    }
}
