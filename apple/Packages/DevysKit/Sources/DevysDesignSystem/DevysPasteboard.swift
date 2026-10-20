#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The Copy affordance's single side effect: writing plain text to the
/// system pasteboard. View chrome only — nothing here touches feature
/// state, so it stays beside the components that invoke it.
public enum DevysPasteboard {
    public static func copy(_ text: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif
    }
}
