import Foundation

// Devys owns the terminal surface theme, but terminal-backed tools such as
// Claude Code and Codex must still be free to render their native ANSI and
// truecolor accents. If NO_COLOR leaks into launched sessions, their color UI
// collapses back to the terminal defaults and the app appears "monochrome."
private let colorSuppressingEnvironmentKeys = ["NO_COLOR"]

func colorSuppressingEnvironmentKeysList() -> [String] {
    colorSuppressingEnvironmentKeys
}

func colorCapableEnvironment(
    _ environment: [String: String]
) -> [String: String] {
    var sanitizedEnvironment = environment
    for key in colorSuppressingEnvironmentKeysList() {
        sanitizedEnvironment.removeValue(forKey: key)
    }
    return sanitizedEnvironment
}

func removeColorSuppressingEnvironmentFromCurrentProcess() {
    for key in colorSuppressingEnvironmentKeysList() {
        unsetenv(key)
    }
}
