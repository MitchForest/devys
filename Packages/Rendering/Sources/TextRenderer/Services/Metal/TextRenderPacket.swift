import Foundation
import simd

public struct TextRenderCell: Sendable, Equatable {
    public let glyph: Character
    public let foregroundColor: SIMD4<Float>
    public let backgroundColor: SIMD4<Float>
    public let flags: UInt32

    public init(
        glyph: Character,
        foregroundColor: SIMD4<Float>,
        backgroundColor: SIMD4<Float>,
        flags: UInt32 = 0
    ) {
        self.glyph = glyph
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.flags = flags
    }
}

public struct TextRenderPacket: Sendable, Equatable {
    public let cells: [TextRenderCell]

    public init(cells: [TextRenderCell]) {
        self.cells = cells
    }

    public static let empty = TextRenderPacket(cells: [])

    public var cellCount: Int {
        cells.count
    }

    public var isEmpty: Bool {
        cells.isEmpty
    }
}

public struct ResolvedTextRenderCell: Sendable, Equatable {
    public let foregroundColor: SIMD4<Float>
    public let backgroundColor: SIMD4<Float>
    public let uvOrigin: SIMD2<Float>
    public let uvSize: SIMD2<Float>
    public let flags: UInt32

    public init(
        foregroundColor: SIMD4<Float>,
        backgroundColor: SIMD4<Float>,
        uvOrigin: SIMD2<Float>,
        uvSize: SIMD2<Float>,
        flags: UInt32
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.uvOrigin = uvOrigin
        self.uvSize = uvSize
        self.flags = flags
    }
}

public struct ResolvedTextRenderPacket: Sendable, Equatable {
    public let cells: [ResolvedTextRenderCell]

    public init(cells: [ResolvedTextRenderCell]) {
        self.cells = cells
    }

    public static let empty = ResolvedTextRenderPacket(cells: [])

    public var cellCount: Int {
        cells.count
    }

    public var isEmpty: Bool {
        cells.isEmpty
    }
}
