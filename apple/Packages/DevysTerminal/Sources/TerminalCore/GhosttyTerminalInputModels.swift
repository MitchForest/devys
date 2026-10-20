import Foundation

public struct GhosttyTerminalKeyEvent: Sendable, Equatable {
    public var key: GhosttyTerminalKey
    public var action: UInt8
    public var text: String?
    public var modifiers: GhosttyTerminalModifiers
    public var unshiftedCodepoint: UInt32

    public init(
        key: GhosttyTerminalKey,
        action: UInt8 = 1,
        text: String? = nil,
        modifiers: GhosttyTerminalModifiers = [],
        unshiftedCodepoint: UInt32 = 0
    ) {
        self.key = key
        self.action = action
        self.text = text
        self.modifiers = modifiers
        self.unshiftedCodepoint = unshiftedCodepoint
    }
}

public struct GhosttyTerminalModifiers: OptionSet, Sendable, Equatable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
}

public struct GhosttyTerminalKey: RawRepresentable, Sendable, Equatable, Hashable {
    public var rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
}

// The canonical key table (raw values are the stable wire encoding the
// VT engine maps onto libghostty key codes). Promoted to public in
// P0-014 so the surface layer's platform input adapters and the VT
// engine share one table instead of duplicating raw values.
// Key constants mirror the physical-key names (a-z, f1-f12); the
// canonical short names beat the identifier-length rule here.
// swiftlint:disable identifier_name
public extension GhosttyTerminalKey {
    static let unidentified = Self(rawValue: 0)
    static let backquote = Self(rawValue: 1)
    static let backslash = Self(rawValue: 2)
    static let bracketLeft = Self(rawValue: 3)
    static let bracketRight = Self(rawValue: 4)
    static let comma = Self(rawValue: 5)
    static let digit0 = Self(rawValue: 6)
    static let digit1 = Self(rawValue: 7)
    static let digit2 = Self(rawValue: 8)
    static let digit3 = Self(rawValue: 9)
    static let digit4 = Self(rawValue: 10)
    static let digit5 = Self(rawValue: 11)
    static let digit6 = Self(rawValue: 12)
    static let digit7 = Self(rawValue: 13)
    static let digit8 = Self(rawValue: 14)
    static let digit9 = Self(rawValue: 15)
    static let equal = Self(rawValue: 16)
    static let intlBackslash = Self(rawValue: 17)
    static let intlRo = Self(rawValue: 18)
    static let intlYen = Self(rawValue: 19)
    static let a = Self(rawValue: 20)
    static let b = Self(rawValue: 21)
    static let c = Self(rawValue: 22)
    static let d = Self(rawValue: 23)
    static let e = Self(rawValue: 24)
    static let f = Self(rawValue: 25)
    static let g = Self(rawValue: 26)
    static let h = Self(rawValue: 27)
    static let i = Self(rawValue: 28)
    static let j = Self(rawValue: 29)
    static let k = Self(rawValue: 30)
    static let l = Self(rawValue: 31)
    static let m = Self(rawValue: 32)
    static let n = Self(rawValue: 33)
    static let o = Self(rawValue: 34)
    static let p = Self(rawValue: 35)
    static let q = Self(rawValue: 36)
    static let r = Self(rawValue: 37)
    static let s = Self(rawValue: 38)
    static let t = Self(rawValue: 39)
    static let u = Self(rawValue: 40)
    static let v = Self(rawValue: 41)
    static let w = Self(rawValue: 42)
    static let x = Self(rawValue: 43)
    static let y = Self(rawValue: 44)
    static let z = Self(rawValue: 45)
    static let minus = Self(rawValue: 46)
    static let period = Self(rawValue: 47)
    static let quote = Self(rawValue: 48)
    static let semicolon = Self(rawValue: 49)
    static let slash = Self(rawValue: 50)
    static let altLeft = Self(rawValue: 51)
    static let altRight = Self(rawValue: 52)
    static let backspace = Self(rawValue: 53)
    static let capsLock = Self(rawValue: 54)
    static let contextMenu = Self(rawValue: 55)
    static let controlLeft = Self(rawValue: 56)
    static let controlRight = Self(rawValue: 57)
    static let enter = Self(rawValue: 58)
    static let metaLeft = Self(rawValue: 59)
    static let metaRight = Self(rawValue: 60)
    static let shiftLeft = Self(rawValue: 61)
    static let shiftRight = Self(rawValue: 62)
    static let space = Self(rawValue: 63)
    static let tab = Self(rawValue: 64)
    static let delete = Self(rawValue: 65)
    static let end = Self(rawValue: 66)
    static let home = Self(rawValue: 67)
    static let insert = Self(rawValue: 68)
    static let pageDown = Self(rawValue: 69)
    static let pageUp = Self(rawValue: 70)
    static let arrowDown = Self(rawValue: 71)
    static let arrowLeft = Self(rawValue: 72)
    static let arrowRight = Self(rawValue: 73)
    static let arrowUp = Self(rawValue: 74)
    static let numLock = Self(rawValue: 75)
    static let numpad0 = Self(rawValue: 76)
    static let numpad1 = Self(rawValue: 77)
    static let numpad2 = Self(rawValue: 78)
    static let numpad3 = Self(rawValue: 79)
    static let numpad4 = Self(rawValue: 80)
    static let numpad5 = Self(rawValue: 81)
    static let numpad6 = Self(rawValue: 82)
    static let numpad7 = Self(rawValue: 83)
    static let numpad8 = Self(rawValue: 84)
    static let numpad9 = Self(rawValue: 85)
    static let numpadAdd = Self(rawValue: 86)
    static let numpadComma = Self(rawValue: 87)
    static let numpadDecimal = Self(rawValue: 88)
    static let numpadDivide = Self(rawValue: 89)
    static let numpadEnter = Self(rawValue: 90)
    static let numpadEqual = Self(rawValue: 91)
    static let numpadMultiply = Self(rawValue: 92)
    static let numpadSubtract = Self(rawValue: 93)
    static let escape = Self(rawValue: 94)
    static let f1 = Self(rawValue: 95)
    static let f2 = Self(rawValue: 96)
    static let f3 = Self(rawValue: 97)
    static let f4 = Self(rawValue: 98)
    static let f5 = Self(rawValue: 99)
    static let f6 = Self(rawValue: 100)
    static let f7 = Self(rawValue: 101)
    static let f8 = Self(rawValue: 102)
    static let f9 = Self(rawValue: 103)
    static let f10 = Self(rawValue: 104)
    static let f11 = Self(rawValue: 105)
    static let f12 = Self(rawValue: 106)
}
// swiftlint:enable identifier_name

public extension GhosttyTerminalModifiers {
    static let shift = Self(rawValue: 1 << 0)
    static let control = Self(rawValue: 1 << 1)
    static let option = Self(rawValue: 1 << 2)
    static let command = Self(rawValue: 1 << 3)
    static let capsLock = Self(rawValue: 1 << 4)
    static let numLock = Self(rawValue: 1 << 5)
    static let rightShift = Self(rawValue: 1 << 6)
    static let rightControl = Self(rawValue: 1 << 7)
    static let rightOption = Self(rawValue: 1 << 8)
    static let rightCommand = Self(rawValue: 1 << 9)
}
