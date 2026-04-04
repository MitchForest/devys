import Foundation

public struct FontStyle: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public static let bold = FontStyle(rawValue: 1 << 0)
    public static let italic = FontStyle(rawValue: 1 << 1)
    public static let underline = FontStyle(rawValue: 1 << 2)

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func parse(_ value: String?) -> FontStyle {
        guard let value else { return [] }

        return value
            .split(whereSeparator: \.isWhitespace)
            .reduce(into: FontStyle()) { style, component in
                switch component.lowercased() {
                case "bold":
                    style.insert(.bold)
                case "italic":
                    style.insert(.italic)
                case "underline":
                    style.insert(.underline)
                default:
                    break
                }
            }
    }
}
