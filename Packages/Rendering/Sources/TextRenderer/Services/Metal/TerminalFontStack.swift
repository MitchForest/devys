import CoreText
import Foundation

public struct TerminalResolvedGlyph {
    let grapheme: String
    let font: CTFont
    let fontIdentifier: String
    let isMissing: Bool

    var usesLastResort: Bool {
        fontIdentifier == TerminalFontStack.lastResortFontIdentifier
    }
}

public struct TerminalFontStack {
    static let lastResortFontIdentifier = "LastResort"
    static let specialRasterizerFontIdentifier = "special-rasterizer"

    let primaryFont: CTFont
    let symbolFallbackFonts: [CTFont]
    let fontSize: CGFloat

    public init(primaryFontName: String, fontSize: CGFloat) {
        self.primaryFont = CTFontCreateWithName(primaryFontName as CFString, fontSize, nil)
        self.symbolFallbackFonts = Self.availableSymbolFallbackFonts(fontSize: fontSize)
        self.fontSize = fontSize
    }

    func resolve(grapheme: String) -> TerminalResolvedGlyph {
        let normalized = grapheme.isEmpty ? " " : grapheme

        if Self.isBlockElement(normalized) {
            return TerminalResolvedGlyph(
                grapheme: normalized,
                font: primaryFont,
                fontIdentifier: Self.specialRasterizerFontIdentifier,
                isMissing: false
            )
        }

        if canRender(normalized, with: primaryFont) {
            return resolved(normalized, font: primaryFont, isMissing: false)
        }

        for fallback in symbolFallbackFonts where canRender(normalized, with: fallback) {
            return resolved(normalized, font: fallback, isMissing: false)
        }

        let cascade = CTFontCreateForString(
            primaryFont,
            normalized as CFString,
            CFRange(location: 0, length: (normalized as NSString).length)
        )
        if canRender(normalized, with: cascade) {
            return resolved(normalized, font: cascade, isMissing: false)
        }

        if TerminalSpecialGlyphRasterizer.canRasterize(normalized) {
            return TerminalResolvedGlyph(
                grapheme: normalized,
                font: primaryFont,
                fontIdentifier: Self.specialRasterizerFontIdentifier,
                isMissing: false
            )
        }

        return TerminalResolvedGlyph(
            grapheme: normalized,
            font: primaryFont,
            fontIdentifier: "missing",
            isMissing: true
        )
    }

    private func resolved(
        _ grapheme: String,
        font: CTFont,
        isMissing: Bool
    ) -> TerminalResolvedGlyph {
        TerminalResolvedGlyph(
            grapheme: grapheme,
            font: font,
            fontIdentifier: CTFontCopyPostScriptName(font) as String,
            isMissing: isMissing
        )
    }

    private func canRender(_ grapheme: String, with font: CTFont) -> Bool {
        let postScriptName = CTFontCopyPostScriptName(font) as String
        guard postScriptName != Self.lastResortFontIdentifier else { return false }

        let characters = Array(grapheme.utf16)
        guard !characters.isEmpty else { return true }
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        let didResolve = characters.withUnsafeBufferPointer { characterBuffer in
            glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                guard let characterBase = characterBuffer.baseAddress,
                      let glyphBase = glyphBuffer.baseAddress
                else {
                    return false
                }
                return CTFontGetGlyphsForCharacters(font, characterBase, glyphBase, characters.count)
            }
        }
        return didResolve && glyphs.allSatisfy { $0 != 0 }
    }

    private static func availableSymbolFallbackFonts(fontSize: CGFloat) -> [CTFont] {
        let bundledFonts = [
            bundledFont(named: "SymbolsNerdFontMono-Regular", extension: "ttf", size: fontSize)
        ].compactMap(\.self)

        let installedFonts = [
            "SymbolsNerdFontMono-Regular",
            "Symbols Nerd Font Mono",
            "SymbolsNerdFont-Regular",
            "Symbols Nerd Font",
            "AppleSymbols",
            "Apple Color Emoji",
        ].compactMap { availableFont(named: $0, size: fontSize) }

        return bundledFonts + installedFonts
    }

    private static func availableFont(named name: String, size: CGFloat) -> CTFont? {
        let descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, size)
        guard let matched = CTFontDescriptorCreateMatchingFontDescriptor(descriptor, nil) else {
            return nil
        }
        return CTFontCreateWithFontDescriptor(matched, size, nil)
    }

    private static func bundledFont(named name: String, extension fileExtension: String, size: CGFloat) -> CTFont? {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Fonts"
        ) else {
            return nil
        }
        guard let provider = CGDataProvider(url: url as CFURL),
              let graphicsFont = CGFont(provider)
        else {
            return nil
        }
        return CTFontCreateWithGraphicsFont(graphicsFont, size, nil, nil)
    }

    private static func isBlockElement(_ grapheme: String) -> Bool {
        guard grapheme.unicodeScalars.count == 1,
              let scalar = grapheme.unicodeScalars.first
        else {
            return false
        }
        return (0x2580...0x259F).contains(scalar.value)
    }
}
