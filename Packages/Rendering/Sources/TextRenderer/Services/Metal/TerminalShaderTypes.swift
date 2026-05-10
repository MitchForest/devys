import Foundation
import simd

public struct TerminalCellGPU {
    public var position: SIMD2<Float>
    public var size: SIMD2<Float>
    public var foregroundColor: SIMD4<Float>
    public var backgroundColor: SIMD4<Float>
    public var uvOrigin: SIMD2<Float>
    public var uvSize: SIMD2<Float>
    public var flags: UInt32
    public var padding: UInt32

    public init(
        position: SIMD2<Float> = .zero,
        size: SIMD2<Float> = .zero,
        foregroundColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        backgroundColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0),
        uvOrigin: SIMD2<Float> = .zero,
        uvSize: SIMD2<Float> = .zero,
        flags: UInt32 = 0
    ) {
        self.position = position
        self.size = size
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.uvOrigin = uvOrigin
        self.uvSize = uvSize
        self.flags = flags
        self.padding = 0
    }
}

public struct TerminalCellFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let bold = TerminalCellFlags(rawValue: 1 << 0)
}

public struct TerminalUniforms {
    public var viewportSize: SIMD2<Float>

    public init(viewportSize: SIMD2<Float> = .zero) {
        self.viewportSize = viewportSize
    }
}

public struct TerminalOverlayVertex {
    public var position: SIMD2<Float>
    public var color: SIMD4<Float>

    public init(position: SIMD2<Float>, color: SIMD4<Float>) {
        self.position = position
        self.color = color
    }
}
