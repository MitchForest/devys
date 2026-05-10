import Foundation

@MainActor
public final class TerminalProductCommandSink {
    private var focusComposerHandler: (() -> Void)?
    private var pasteIntoComposerHandler: (() -> Void)?
    private var captureSelectionIntoComposerHandler: (() -> Void)?

    public init() {}

    func install(
        focusComposer: @escaping () -> Void,
        pasteIntoComposer: @escaping () -> Void,
        captureSelectionIntoComposer: @escaping () -> Void
    ) {
        focusComposerHandler = focusComposer
        pasteIntoComposerHandler = pasteIntoComposer
        captureSelectionIntoComposerHandler = captureSelectionIntoComposer
    }

    func clear() {
        focusComposerHandler = nil
        pasteIntoComposerHandler = nil
        captureSelectionIntoComposerHandler = nil
    }

    public func focusComposer() {
        focusComposerHandler?()
    }

    public func pasteIntoComposer() {
        pasteIntoComposerHandler?()
    }

    public func captureSelectionIntoComposer() {
        captureSelectionIntoComposerHandler?()
    }
}
