import SwiftUI
import Workspace

extension AppearanceMode {
    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .auto: systemColorScheme
        case .light: .light
        case .dark: .dark
        }
    }
}
