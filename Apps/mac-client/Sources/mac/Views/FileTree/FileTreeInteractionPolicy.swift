import AppKit

enum FileTreePrimaryClickBehavior: Equatable {
    case selectRange
    case toggleSelection
    case selectAndToggleDirectory
    case selectAndPreviewFile
}

func fileTreePrimaryClickBehavior(
    isDirectory: Bool,
    modifiers: NSEvent.ModifierFlags
) -> FileTreePrimaryClickBehavior {
    if modifiers.contains(.shift) {
        return .selectRange
    }

    if modifiers.contains(.command) {
        return .toggleSelection
    }

    return isDirectory ? .selectAndToggleDirectory : .selectAndPreviewFile
}
