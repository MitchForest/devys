import CoreGraphics
import GhosttyTerminalCore
import SwiftUI

public extension GhosttyTerminalView {
    init(
        surfaceState: GhosttyTerminalSurfaceState,
        frameProjection: GhosttyTerminalFrameProjection,
        appearance: GhosttyTerminalAppearance = .defaultDark,
        selectionMode: Bool = true,
        focusRequestID: Int = 0,
        onFirstAtlasMutation: @escaping () -> Void = {},
        onFirstFrameCommit: @escaping () -> Void = {},
        onFirstInteractiveFrame: @escaping () -> Void = {},
        onRenderFailure: @escaping (String) -> Void = { _ in },
        onTap: @escaping () -> Void = {},
        onSelectionBegin: @escaping (Int, Int) -> Void = { _, _ in },
        onSelectionMove: @escaping (Int, Int) -> Void = { _, _ in },
        onSelectionEnd: @escaping () -> Void = {},
        onSelectWord: @escaping (Int, Int) -> Void = { _, _ in },
        onClearSelection: @escaping () -> Void = {},
        onScroll: @escaping (Int) -> Void = { _ in },
        onViewportSizeChange: @escaping (CGSize, Int, Int, Int, Int) -> Void = { _, _, _, _, _ in },
        onSendText: @escaping (String) -> Void = { _ in },
        onSendSpecialKey: @escaping (GhosttyTerminalSpecialKey) -> Void = { _ in },
        onSendControlCharacter: @escaping (Character) -> Void = { _ in },
        onSendAltText: @escaping (String) -> Void = { _ in },
        onPasteText: @escaping (String) -> Void = { _ in },
        selectionTextProvider: @escaping () -> String? = { nil }
    ) {
        self.surfaceState = surfaceState
        self.frameProjection = frameProjection
        self.appearance = appearance
        self.selectionMode = selectionMode
        self.focusRequestID = focusRequestID
        self.callbacks = GhosttyTerminalViewCallbacks(
            onTap: onTap,
            onSelectionBegin: onSelectionBegin,
            onSelectionMove: onSelectionMove,
            onSelectionEnd: onSelectionEnd,
            onSelectWord: onSelectWord,
            onClearSelection: onClearSelection,
            onScroll: onScroll,
            onViewportSizeChange: onViewportSizeChange,
            onSendText: onSendText,
            onSendSpecialKey: onSendSpecialKey,
            onSendControlCharacter: onSendControlCharacter,
            onSendAltText: onSendAltText,
            onPasteText: onPasteText,
            selectionTextProvider: selectionTextProvider,
            onFirstAtlasMutation: onFirstAtlasMutation,
            onFirstFrameCommit: onFirstFrameCommit,
            onFirstInteractiveFrame: onFirstInteractiveFrame,
            onRenderFailure: onRenderFailure
        )
    }

    var body: some View {
        GhosttyTerminalPlatformView(
            surfaceState: surfaceState,
            frameProjection: frameProjection,
            appearance: appearance,
            selectionMode: selectionMode,
            focusRequestID: focusRequestID,
            callbacks: callbacks
        )
    }
}
