import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

public enum TreeSitterBootstrap {
    public static func makeParser() -> Parser {
        Parser()
    }

    public static var supportsLanguageLayers: Bool {
        _ = LanguageLayer.self
        return true
    }
}
