public import SwiftUI

/// SF Pro throughout; New York only for the daily greeting. macOS uses the
/// fixed sizes the design is measured at; iOS maps each token to a Dynamic
/// Type style so text follows the reader's chosen size.
public enum DevysTypography {
    #if os(iOS)
        public static let greeting = Font.system(.largeTitle, design: .serif, weight: .medium)
        public static let title = Font.system(.title2, weight: .semibold)
        public static let heading = Font.system(.headline)
        public static let body = Font.system(.subheadline)
        public static let secondary = Font.system(.footnote)
        public static let label = Font.system(.caption, weight: .semibold)
        public static let caption = Font.system(.caption, weight: .medium)
        public static let control = Font.system(.subheadline, weight: .medium)
        public static let data = Font.system(.caption, design: .monospaced)
    #else
        public static let greeting = Font.system(size: 34, weight: .medium, design: .serif)
        public static let title = Font.system(size: 22, weight: .semibold)
        public static let heading = Font.system(size: 15, weight: .semibold)
        public static let body = Font.system(size: 13.5)
        public static let secondary = Font.system(size: 12.5)
        public static let label = Font.system(size: 11, weight: .semibold)
        public static let caption = Font.system(size: 12, weight: .medium)
        public static let control = Font.system(size: 13, weight: .medium)
        public static let data = Font.system(size: 12, design: .monospaced)
    #endif
}
