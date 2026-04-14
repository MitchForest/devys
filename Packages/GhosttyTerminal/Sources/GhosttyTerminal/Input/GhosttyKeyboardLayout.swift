import Foundation

#if canImport(GhosttyKit) && os(macOS)
import Carbon

enum GhosttyKeyboardLayout {
    static var id: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let sourceIDPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else {
            return nil
        }

        let sourceID = unsafeBitCast(sourceIDPointer, to: CFString.self)
        return sourceID as String
    }
}
#endif
