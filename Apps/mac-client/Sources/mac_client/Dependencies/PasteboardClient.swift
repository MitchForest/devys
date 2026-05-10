import AppKit
import ComposableArchitecture
import Foundation

struct PasteboardClient: Sendable {
    var readString: @Sendable () async -> String?
    var writeString: @Sendable (String) async -> Void

    init(
        readString: @escaping @Sendable () async -> String?,
        writeString: @escaping @Sendable (String) async -> Void
    ) {
        self.readString = readString
        self.writeString = writeString
    }
}

private enum PasteboardClientKey: DependencyKey {
    static let liveValue = PasteboardClient(
        readString: {
            await MainActor.run {
                NSPasteboard.general.string(forType: .string)
            }
        },
        writeString: { string in
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(string, forType: .string)
            }
        }
    )
}

extension DependencyValues {
    var pasteboardClient: PasteboardClient {
        get { self[PasteboardClientKey.self] }
        set { self[PasteboardClientKey.self] = newValue }
    }
}
