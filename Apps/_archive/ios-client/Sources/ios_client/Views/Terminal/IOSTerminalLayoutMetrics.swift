import SwiftUI
import UIKit

enum IOSTerminalLayoutMetrics {
    static let uiFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let swiftUIFont = Font(uiFont)

    static let cellWidth: CGFloat = {
        let glyph = ("M" as NSString).size(withAttributes: [.font: uiFont])
        return max(6.0, glyph.width)
    }()

    static let cellHeight: CGFloat = max(12.0, ceil(uiFont.lineHeight))
}
