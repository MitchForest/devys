import Foundation

struct TerminalSpecialGlyphBitmap: Equatable {
    let rgba: [UInt8]
    let width: Int
    let height: Int
}

enum TerminalSpecialGlyphRasterizer {
    static func canRasterize(_ grapheme: String) -> Bool {
        guard grapheme.unicodeScalars.count == 1,
              let scalar = grapheme.unicodeScalars.first
        else {
            return false
        }

        return isBlockElement(scalar.value) || isPrivateUseSymbol(scalar.value)
    }

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
        case 0xE000...0xF8FF:
            return privateUseSymbolBitmap(
                for: scalar.value,
                cellWidth: cellWidth,
                cellHeight: cellHeight
            )
        default:
            return nil
        }
    }

    private static func isBlockElement(_ scalar: UInt32) -> Bool {
        (0x2580...0x259F).contains(scalar)
    }

    private static func isPrivateUseSymbol(_ scalar: UInt32) -> Bool {
        (0xE000...0xF8FF).contains(scalar)
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

    private static func privateUseSymbolBitmap(
        for scalar: UInt32,
        cellWidth: Int,
        cellHeight: Int
    ) -> TerminalSpecialGlyphBitmap {
        var canvas = BlockBitmapCanvas(cellWidth: cellWidth, cellHeight: cellHeight)
        if isFolderSymbol(scalar) {
            canvas.drawFolder()
        } else if isImageFileSymbol(scalar) {
            canvas.drawFileBadge(kind: .image)
        } else if isCodeFileSymbol(scalar) {
            canvas.drawFileBadge(kind: .code)
        } else {
            canvas.drawFileBadge(kind: .generic)
        }
        return TerminalSpecialGlyphBitmap(
            rgba: canvas.rgba,
            width: cellWidth,
            height: cellHeight
        )
    }

    private static func isFolderSymbol(_ scalar: UInt32) -> Bool {
        scalar == 0xF07B || scalar == 0xF115 || scalar == 0xE5FF || scalar == 0xEA83
    }

    private static func isImageFileSymbol(_ scalar: UInt32) -> Bool {
        scalar == 0xF1C5 || scalar == 0xF03E || scalar == 0xEB9F
    }

    private static func isCodeFileSymbol(_ scalar: UInt32) -> Bool {
        (0xE700...0xE7FF).contains(scalar) ||
            scalar == 0xE628 ||
            scalar == 0xE781 ||
            scalar == 0xF121
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

    mutating func drawFolder() {
        let insetX = max(1, cellWidth / 8)
        let insetY = max(1, cellHeight / 5)
        let tabWidth = max(2, cellWidth / 3)
        let tabHeight = max(1, cellHeight / 5)
        let bodyY = insetY + tabHeight
        let bodyHeight = max(1, cellHeight - bodyY - insetY)
        let bodyWidth = max(1, cellWidth - insetX * 2)

        fillRect(x: insetX, y: insetY, width: tabWidth, height: tabHeight)
        fillRect(x: insetX, y: bodyY, width: bodyWidth, height: bodyHeight)
    }

    mutating func drawFileBadge(kind: TerminalPrivateUseSymbolKind) {
        let insetX = max(1, cellWidth / 5)
        let insetY = max(1, cellHeight / 8)
        let width = max(1, cellWidth - insetX * 2)
        let height = max(1, cellHeight - insetY * 2)
        let fold = max(1, min(width, height) / 4)

        drawRect(x: insetX, y: insetY, width: width, height: height, thickness: max(1, cellWidth / 10))
        fillRect(x: insetX + width - fold, y: insetY, width: fold, height: fold)

        switch kind {
        case .code:
            drawCodeMark(x: insetX, y: insetY, width: width, height: height)
        case .image:
            drawImageMark(x: insetX, y: insetY, width: width, height: height)
        case .generic:
            drawGenericLines(x: insetX, y: insetY, width: width, height: height)
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

    private mutating func drawRect(x: Int, y: Int, width: Int, height: Int, thickness: Int) {
        fillRect(x: x, y: y, width: width, height: thickness)
        fillRect(x: x, y: y + height - thickness, width: width, height: thickness)
        fillRect(x: x, y: y, width: thickness, height: height)
        fillRect(x: x + width - thickness, y: y, width: thickness, height: height)
    }

    private mutating func drawCodeMark(x: Int, y: Int, width: Int, height: Int) {
        let stroke = max(1, cellWidth / 10)
        let midY = y + height / 2
        fillRect(x: x + width / 4, y: midY - stroke, width: stroke, height: stroke)
        fillRect(x: x + width / 4 + stroke, y: midY - stroke * 2, width: stroke, height: stroke)
        fillRect(x: x + width / 4 + stroke, y: midY, width: stroke, height: stroke)
        fillRect(x: x + width - width / 4 - stroke, y: midY - stroke, width: stroke, height: stroke)
        fillRect(x: x + width - width / 4 - stroke * 2, y: midY - stroke * 2, width: stroke, height: stroke)
        fillRect(x: x + width - width / 4 - stroke * 2, y: midY, width: stroke, height: stroke)
    }

    private mutating func drawImageMark(x: Int, y: Int, width: Int, height: Int) {
        let stroke = max(1, cellWidth / 10)
        let baseY = y + height - max(2, height / 4)
        fillRect(x: x + width / 4, y: y + height / 3, width: stroke * 2, height: stroke * 2)
        fillRect(x: x + width / 5, y: baseY, width: width / 2, height: stroke)
        fillRect(x: x + width / 2, y: baseY - stroke, width: width / 3, height: stroke)
    }

    private mutating func drawGenericLines(x: Int, y: Int, width: Int, height: Int) {
        let stroke = max(1, cellWidth / 10)
        let lineWidth = max(1, width / 2)
        fillRect(x: x + width / 4, y: y + height / 2 - stroke, width: lineWidth, height: stroke)
        fillRect(x: x + width / 4, y: y + height / 2 + stroke * 2, width: lineWidth, height: stroke)
    }

    private mutating func setPixel(x: Int, y: Int) {
        let index = ((y * cellWidth) + x) * 4
        rgba[index + 0] = 255
        rgba[index + 1] = 255
        rgba[index + 2] = 255
        rgba[index + 3] = 255
    }
}

private enum TerminalPrivateUseSymbolKind {
    case code
    case generic
    case image
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
