import CoreGraphics
import CoreText
import Foundation

enum RequiredEditorFont {
    static func make(name: String, size: CGFloat) -> CTFont {
        let descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, size)
        guard let matchedDescriptor = CTFontDescriptorCreateMatchingFontDescriptor(descriptor, nil) else {
            preconditionFailure("Required editor font '\(name)' is not available.")
        }

        let font = CTFontCreateWithFontDescriptor(matchedDescriptor, size, nil)
        let resolvedName = CTFontCopyPostScriptName(font) as String
        guard resolvedName == name else {
            preconditionFailure("Required editor font '\(name)' resolved to '\(resolvedName)'.")
        }

        return font
    }
}
