import Foundation

struct TerminalSpecialGlyphBitmap: Equatable {
    let rgba: [UInt8]
    let width: Int
    let height: Int
}

enum TerminalSpecialGlyphRasterizer {
    static func bitmap(
        for grapheme: String,
        cellWidth: Int,
        cellHeight: Int
    ) -> TerminalSpecialGlyphBitmap? {
        guard cellWidth > 0,
              cellHeight > 0,
              grapheme.unicodeScalars.count == 1,
              let scalar = grapheme.unicodeScalars.first
        else {
            return nil
        }

        switch scalar.value {
        case 0x2580...0x259F:
            return blockElementBitmap(
                for: scalar.value,
                cellWidth: cellWidth,
                cellHeight: cellHeight
            )
        default:
            return nil
        }
    }

    private static func blockElementBitmap(
        for scalar: UInt32,
        cellWidth: Int,
        cellHeight: Int
    ) -> TerminalSpecialGlyphBitmap {
        guard let instruction = instruction(for: scalar) else {
            return TerminalSpecialGlyphBitmap(
                rgba: [UInt8](repeating: 0, count: cellWidth * cellHeight * 4),
                width: cellWidth,
                height: cellHeight
            )
        }

        var canvas = BlockBitmapCanvas(cellWidth: cellWidth, cellHeight: cellHeight)
        canvas.apply(instruction)
        return TerminalSpecialGlyphBitmap(
            rgba: canvas.rgba,
            width: cellWidth,
            height: cellHeight
        )
    }

    private static func instruction(for scalar: UInt32) -> BlockFillInstruction? {
        if let instruction = eighthsInstruction(for: scalar) {
            return instruction
        }
        if let instruction = shadeInstruction(for: scalar) {
            return instruction
        }
        return quadrantInstruction(for: scalar)
    }

    private static func eighthsInstruction(for scalar: UInt32) -> BlockFillInstruction? {
        switch scalar {
        case 0x2580:
            .upperEighths(4)
        case 0x2581...0x2588:
            .lowerEighths(Int(scalar - 0x2580))
        case 0x2589...0x258F:
            .leftEighths(Int(0x2590 - scalar))
        case 0x2590:
            .rightEighths(4)
        case 0x2594:
            .upperEighths(1)
        case 0x2595:
            .rightEighths(1)
        default:
            nil
        }
    }

    private static func shadeInstruction(for scalar: UInt32) -> BlockFillInstruction? {
        switch scalar {
        case 0x2591:
            .shade(.light)
        case 0x2592:
            .shade(.medium)
        case 0x2593:
            .shade(.dark)
        default:
            nil
        }
    }

    private static func quadrantInstruction(for scalar: UInt32) -> BlockFillInstruction? {
        switch scalar {
        case 0x2596:
            .quadrants([.lowerLeft])
        case 0x2597:
            .quadrants([.lowerRight])
        case 0x2598:
            .quadrants([.upperLeft])
        case 0x2599:
            .quadrants([.upperLeft, .lowerLeft, .lowerRight])
        case 0x259A:
            .quadrants([.upperLeft, .lowerRight])
        case 0x259B:
            .quadrants([.upperLeft, .upperRight, .lowerLeft])
        case 0x259C:
            .quadrants([.upperLeft, .upperRight, .lowerRight])
        case 0x259D:
            .quadrants([.upperRight])
        case 0x259E:
            .quadrants([.upperRight, .lowerLeft])
        case 0x259F:
            .quadrants([.upperRight, .lowerLeft, .lowerRight])
        default:
            nil
        }
    }

    fileprivate static func scaledPixels(
        total: Int,
        numerator: Int,
        denominator: Int
    ) -> Int {
        max(1, Int(ceil(Double(total * numerator) / Double(denominator))))
    }

}

private struct BlockBitmapCanvas {
    var rgba: [UInt8]
    let cellWidth: Int
    let cellHeight: Int

    init(cellWidth: Int, cellHeight: Int) {
        self.rgba = [UInt8](repeating: 0, count: cellWidth * cellHeight * 4)
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
    }

    mutating func apply(_ instruction: BlockFillInstruction) {
        switch instruction {
        case .upperEighths(let eighths):
            fillUpperEighths(eighths)
        case .lowerEighths(let eighths):
            fillLowerEighths(eighths)
        case .leftEighths(let eighths):
            fillLeftEighths(eighths)
        case .rightEighths(let eighths):
            fillRightEighths(eighths)
        case .quadrants(let quadrants):
            fillQuadrants(quadrants)
        case .shade(let shade):
            fillShade(shade)
        }
    }

    private mutating func fillUpperEighths(_ eighths: Int) {
        let filledHeight = TerminalSpecialGlyphRasterizer.scaledPixels(
            total: cellHeight,
            numerator: eighths,
            denominator: 8
        )
        fillRect(x: 0, y: 0, width: cellWidth, height: filledHeight)
    }

    private mutating func fillLowerEighths(_ eighths: Int) {
        let filledHeight = TerminalSpecialGlyphRasterizer.scaledPixels(
            total: cellHeight,
            numerator: eighths,
            denominator: 8
        )
        fillRect(x: 0, y: cellHeight - filledHeight, width: cellWidth, height: filledHeight)
    }

    private mutating func fillLeftEighths(_ eighths: Int) {
        let filledWidth = TerminalSpecialGlyphRasterizer.scaledPixels(
            total: cellWidth,
            numerator: eighths,
            denominator: 8
        )
        fillRect(x: 0, y: 0, width: filledWidth, height: cellHeight)
    }

    private mutating func fillRightEighths(_ eighths: Int) {
        let filledWidth = TerminalSpecialGlyphRasterizer.scaledPixels(
            total: cellWidth,
            numerator: eighths,
            denominator: 8
        )
        fillRect(x: cellWidth - filledWidth, y: 0, width: filledWidth, height: cellHeight)
    }

    private mutating func fillQuadrants(_ quadrants: Set<BlockQuadrant>) {
        let leftWidth = (cellWidth + 1) / 2
        let rightWidth = cellWidth - leftWidth
        let topHeight = (cellHeight + 1) / 2
        let bottomHeight = cellHeight - topHeight

        if quadrants.contains(.upperLeft) {
            fillRect(x: 0, y: 0, width: leftWidth, height: topHeight)
        }
        if quadrants.contains(.upperRight) {
            fillRect(x: leftWidth, y: 0, width: rightWidth, height: topHeight)
        }
        if quadrants.contains(.lowerLeft) {
            fillRect(x: 0, y: topHeight, width: leftWidth, height: bottomHeight)
        }
        if quadrants.contains(.lowerRight) {
            fillRect(x: leftWidth, y: topHeight, width: rightWidth, height: bottomHeight)
        }
    }

    private mutating func fillShade(_ shade: BlockShade) {
        for row in 0..<cellHeight {
            for column in 0..<cellWidth where shade.includes(column: column, row: row) {
                setPixel(x: column, y: row)
            }
        }
    }

    private mutating func fillRect(x: Int, y: Int, width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        let minX = max(0, x)
        let minY = max(0, y)
        let maxX = min(cellWidth, x + width)
        let maxY = min(cellHeight, y + height)
        guard maxX > minX, maxY > minY else { return }

        for row in minY..<maxY {
            for column in minX..<maxX {
                setPixel(x: column, y: row)
            }
        }
    }

    private mutating func setPixel(x: Int, y: Int) {
        let index = ((y * cellWidth) + x) * 4
        rgba[index + 0] = 255
        rgba[index + 1] = 255
        rgba[index + 2] = 255
        rgba[index + 3] = 255
    }
}

private enum BlockFillInstruction {
    case upperEighths(Int)
    case lowerEighths(Int)
    case leftEighths(Int)
    case rightEighths(Int)
    case quadrants(Set<BlockQuadrant>)
    case shade(BlockShade)
}

private enum BlockShade {
    case light
    case medium
    case dark

    func includes(column: Int, row: Int) -> Bool {
        let sum = column + row
        switch self {
        case .light:
            return sum.isMultiple(of: 4)
        case .medium:
            return sum.isMultiple(of: 2)
        case .dark:
            return sum.isMultiple(of: 4) == false
        }
    }
}

private enum BlockQuadrant: CaseIterable {
    case upperLeft
    case upperRight
    case lowerLeft
    case lowerRight
}
