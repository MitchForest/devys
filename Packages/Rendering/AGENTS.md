# DevysTextRenderer

A high-performance Metal-based text rendering package for macOS text editors. This package provides GPU-accelerated text rendering using a glyph atlas approach, optimized for displaying monospace text with syntax highlighting.

## Overview

DevysTextRenderer is a Swift 6 package that renders text using Metal shaders. It is designed specifically for code editor use cases where:

- Text is rendered in a monospace font (default: Menlo)
- Each character occupies a fixed-width cell
- High frame rates are required with potentially thousands of visible characters
- Characters need individual styling (colors, attributes)

The package uses a glyph atlas texture approach: characters are pre-rendered to a texture atlas, and the GPU assembles the final image by sampling from this atlas for each character cell.

## Architecture

### Rendering Pipeline

```
CPU Side:
1. EditorMetrics - Calculate cell sizes, line heights from font metrics
2. EditorGlyphAtlas - Pre-render glyphs to texture atlas
3. EditorCellBuffer - Build per-frame cell data arrays
4. EditorOverlayBuffer - Build overlay geometry (cursor, selection)

GPU Side:
5. EditorShaders.metal - Vertex/fragment shaders render cells and overlays
```

### Data Flow

1. **Font Metrics Calculation**: `EditorMetrics.measure()` uses CoreText to determine cell dimensions
2. **Glyph Pre-rendering**: `EditorGlyphAtlas` renders ASCII characters to a 2048x2048 texture atlas
3. **Per-frame Cell Building**: For each visible character, create an `EditorCellGPU` struct with position, colors, and UV coordinates
4. **Triple-buffered Upload**: `EditorCellBuffer` uses triple-buffering for CPU/GPU synchronization
5. **Instanced Drawing**: GPU renders one quad per character using instanced drawing
6. **Overlay Rendering**: Cursor and selection quads are rendered via separate pipeline

## File Organization

```
Sources/DevysTextRenderer/
├── Resources/
│   └── EditorShaders.metal       # Metal vertex/fragment shaders
└── Services/
    ├── Metal/
    │   ├── EditorCellBuffer.swift    # GPU buffers for cell data
    │   ├── EditorGlyphAtlas.swift    # Glyph texture atlas
    │   ├── EditorMetrics.swift       # Font metrics and layout
    │   ├── EditorRenderPipeline.swift # Metal pipeline setup
    │   └── EditorShaderTypes.swift   # Shared Swift/Metal types
    └── ScrollWheelNormalizer.swift   # macOS scroll wheel handling
```

## Key Types

### EditorMetrics

Calculates and stores font-based layout metrics.

```swift
public struct EditorMetrics: Equatable, Sendable {
    public let cellWidth: CGFloat      // Width of one character cell
    public let lineHeight: CGFloat     // Height of one line
    public let fontSize: CGFloat       // Font size in points
    public let baseline: CGFloat       // Baseline offset from top
    public let fontName: String        // Font family name
    public let gutterWidth: CGFloat    // Width of line number gutter

    // Factory method to measure font metrics
    public static func measure(fontSize: CGFloat, fontName: String = "Menlo") -> EditorMetrics

    // Layout helpers
    public func visibleLines(for viewportHeight: CGFloat) -> Int
    public func yPosition(forLine index: Int) -> CGFloat
    public func lineAt(y: CGFloat) -> Int
    public func xPosition(forColumn col: Int) -> CGFloat
    public func columnAt(x: CGFloat) -> Int
}
```

### EditorGlyphAtlas

Manages the GPU texture atlas containing pre-rendered glyphs.

```swift
@MainActor
public final class EditorGlyphAtlas {
    public init(
        device: MTLDevice,
        fontName: String = "Menlo",
        fontSize: CGFloat = 13,
        scaleFactor: CGFloat = 2.0,  // Retina support
        atlasSize: Int = 2048
    )

    public private(set) var texture: MTLTexture?
    public let cellWidth: Int
    public let cellHeight: Int

    // Get UV coordinates for a character
    public func entry(for char: Character) -> GlyphAtlasEntry
    public var glyphCount: Int
    public func hasGlyph(_ char: Character) -> Bool
}
```

### EditorCellBuffer

Triple-buffered GPU buffer for cell data.

```swift
@MainActor
public final class EditorCellBuffer {
    public init(device: MTLDevice, initialCapacity: Int = 10000)

    public var currentBuffer: MTLBuffer
    public private(set) var cellCount: Int

    // Frame building API
    public func beginFrame()
    public func addCell(_ cell: EditorCellGPU)
    public func addCells(_ cells: [EditorCellGPU])
    public func endFrame()
    public func syncToGPU()
    public func advanceBuffer()
    public func clear()
}
```

### EditorOverlayBuffer

Buffer for cursor and selection overlay quads.

```swift
@MainActor
public final class EditorOverlayBuffer {
    public init(device: MTLDevice, initialCapacity: Int = 1000)

    public var currentBuffer: MTLBuffer?
    public private(set) var vertexCount: Int

    public func clear()
    public func addQuad(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>)
    public func syncToGPU()
}
```

### EditorCellGPU

Per-character data structure sent to the GPU (mirrors Metal shader struct).

```swift
public struct EditorCellGPU {
    public var position: SIMD2<Float>         // Pixel position (x, y)
    public var foregroundColor: SIMD4<Float>  // Text color (linear RGBA)
    public var backgroundColor: SIMD4<Float>  // Background color (linear RGBA)
    public var uvOrigin: SIMD2<Float>         // Glyph atlas UV origin
    public var uvSize: SIMD2<Float>           // Glyph atlas UV size
    public var flags: UInt32                  // Cell attribute flags
    public var padding: UInt32                // Alignment padding
}
```

### EditorCellFlags

Bit flags for character attributes.

```swift
public struct EditorCellFlags: OptionSet, Sendable {
    public static let bold          = EditorCellFlags(rawValue: 1 << 0)
    public static let italic        = EditorCellFlags(rawValue: 1 << 1)
    public static let underline     = EditorCellFlags(rawValue: 1 << 2)
    public static let strikethrough = EditorCellFlags(rawValue: 1 << 3)
    public static let dim           = EditorCellFlags(rawValue: 1 << 4)  // Applied in shader
    public static let cursor        = EditorCellFlags(rawValue: 1 << 5)
    public static let selection     = EditorCellFlags(rawValue: 1 << 6)
    public static let lineNumber    = EditorCellFlags(rawValue: 1 << 7)
}
```

### EditorUniforms

Per-frame uniform data for GPU.

```swift
public struct EditorUniforms {
    public var viewportSize: SIMD2<Float>     // Viewport in pixels
    public var cellSize: SIMD2<Float>         // Cell size in pixels
    public var atlasSize: SIMD2<Float>        // Glyph atlas dimensions
    public var time: Float                    // Animation time
    public var cursorBlinkRate: Float         // Cursor blink rate (Hz)
}
```

### EditorRenderPipeline

Metal pipeline state management.

```swift
@MainActor
public final class EditorRenderPipeline {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let cellPipeline: MTLRenderPipelineState     // Text rendering
    public let overlayPipeline: MTLRenderPipelineState  // Cursor/selection

    public init(device: MTLDevice) throws
}
```

### ScrollWheelNormalizer

Utility for normalizing macOS scroll wheel events.

```swift
public enum ScrollWheelNormalizer {
    // Returns normalized pixel delta matching NSScrollView behavior
    public static func pixelDelta(for event: NSEvent, lineHeight: CGFloat) -> CGFloat
}
```

## Dependencies

This package has **no external dependencies**. It uses only Apple frameworks:

- **Foundation** - Basic types and utilities
- **Metal** - GPU rendering
- **MetalKit** - Metal utilities
- **CoreText** - Font metrics and glyph rendering
- **CoreGraphics** - 2D graphics for glyph rasterization
- **OSLog** - Logging
- **AppKit** (macOS only) - Scroll wheel event handling
- **simd** - SIMD vector types

## Metal Shaders

Located in `Sources/DevysTextRenderer/Resources/EditorShaders.metal`:

### Cell Rendering

- **editorCellVertexShader**: Instanced vertex shader that generates quad vertices for each character cell
- **editorCellFragmentShader**: Samples glyph alpha from atlas and blends foreground/background colors

### Overlay Rendering

- **editorOverlayVertexShader**: Transforms overlay vertex positions to NDC
- **editorOverlayFragmentShader**: Outputs solid colors for cursor/selection

### Background Rendering

- **editorBackgroundVertexShader**: Simple vertex passthrough
- **editorBackgroundFragmentShader**: Outputs solid background color

## Rendering Patterns

### Typical Frame Render Sequence

```swift
// 1. Begin frame
cellBuffer.beginFrame()

// 2. For each visible character
for line in visibleLines {
    for (column, char) in line.enumerated() {
        let entry = glyphAtlas.entry(for: char)
        let cell = EditorCellGPU(
            position: SIMD2<Float>(Float(xPos), Float(yPos)),
            foregroundColor: syntaxColor,
            backgroundColor: .zero,
            uvOrigin: entry.uvOrigin,
            uvSize: entry.uvSize,
            flags: 0
        )
        cellBuffer.addCell(cell)
    }
}

// 3. End frame and sync to GPU
cellBuffer.endFrame()
cellBuffer.syncToGPU()

// 4. Build overlays
overlayBuffer.clear()
overlayBuffer.addQuad(x: cursorX, y: cursorY, width: 2, height: lineHeight, color: cursorColor)
overlayBuffer.syncToGPU()

// 5. Render
encoder.setRenderPipelineState(pipeline.cellPipeline)
encoder.setVertexBuffer(cellBuffer.currentBuffer, offset: 0, index: 0)
encoder.setVertexBytes(&uniforms, length: MemoryLayout<EditorUniforms>.size, index: 1)
encoder.setFragmentTexture(glyphAtlas.texture, index: 0)
encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: cellBuffer.cellCount)

// 6. Advance buffer for next frame
cellBuffer.advanceBuffer()
```

### Color Space Handling

Colors are expected in **linear RGB** color space. Use the provided utility functions:

```swift
// Convert sRGB (0-1) to linear
let linearValue = srgbToLinear(srgbValue)

// Convert hex color to linear SIMD4
let color = hexToLinearColor("#FF5733")
let colorWithAlpha = hexToLinearColor("#FF5733", alpha: 0.8)
```

### Glyph Atlas Management

The atlas pre-loads printable ASCII characters (0x20-0x7E) at initialization. Additional characters are added on-demand:

```swift
// This will add the character if not present
let entry = glyphAtlas.entry(for: char)
```

If the atlas fills up, fallback behavior returns the space character's entry.

## Conventions

1. **MainActor**: All mutable GPU resource classes are `@MainActor` for thread safety
2. **Triple Buffering**: `EditorCellBuffer` uses 3 buffers to avoid CPU/GPU contention
3. **Managed Storage**: Metal buffers use `.storageModeManaged` with explicit `didModifyRange` calls
4. **Pixel Coordinates**: All positions are in pixels, with Y-axis flipped in shaders for Metal's coordinate system
5. **Linear Colors**: All colors passed to GPU are in linear color space (not sRGB)
6. **Instanced Drawing**: Text cells are rendered using instanced triangle strips (4 vertices per cell)

## Platform Support

- **macOS 14+** (Sonoma and later)
- **Swift 6.0** with strict concurrency checking
- **Retina Display Support**: Configurable scale factor (default 2.0x)

## Error Handling

`EditorRenderError` enum covers Metal initialization failures:

```swift
public enum EditorRenderError: Error, LocalizedError {
    case failedToCreateCommandQueue
    case failedToLoadShaders
    case shaderFunctionNotFound(String)
    case failedToCreatePipeline(String)
}
```

## Performance Notes

- Pre-loads ~95 ASCII glyphs at startup
- Triple-buffered cell data eliminates CPU/GPU sync stalls
- Instanced rendering minimizes draw calls (one draw call for all text)
- Atlas texture is 2048x2048 RGBA (16MB), supporting thousands of unique characters
- Cell buffer auto-grows (doubles capacity when exceeded)
