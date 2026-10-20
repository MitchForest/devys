// Ported from the reference repo's TerminalSurface host layer (P0-014).

import CoreGraphics
import SwiftUI
import TerminalSurfaceCore
import TerminalVT

extension GhosttyTerminalView {
    init(
        renderSession: TerminalSurfaceRenderSession,
        appearance: TerminalAppearance = .defaultDark,
        fontSize: CGFloat = TerminalSurfaceDefaults.fontSize,
        selectionMode: Bool = true,
        focusRequestID: Int = 0,
        isSurfaceVisible: Bool = true,
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
        onScroll: @escaping (TerminalSurfaceScrollEvent) -> Void = { _ in },
        onSurfaceSizeChange: @escaping (TerminalSurfacePixelSize) -> Void = { _ in },
        onInput: @escaping (TerminalSurfaceInputCommand) -> Void = { _ in },
        selectionTextProvider: @escaping () -> String? = { nil }
    ) {
        self.renderSession = renderSession
        self.appearance = appearance
        self.fontSize = fontSize
        self.selectionMode = selectionMode
        self.focusRequestID = focusRequestID
        self.isSurfaceVisible = isSurfaceVisible
        self.callbacks = GhosttyTerminalViewCallbacks(
            onTap: onTap,
            onSelectionBegin: onSelectionBegin,
            onSelectionMove: onSelectionMove,
            onSelectionEnd: onSelectionEnd,
            onSelectWord: onSelectWord,
            onClearSelection: onClearSelection,
            onScroll: onScroll,
            onSurfaceSizeChange: onSurfaceSizeChange,
            onInput: onInput,
            selectionTextProvider: selectionTextProvider,
            onFirstAtlasMutation: onFirstAtlasMutation,
            onFirstFrameCommit: onFirstFrameCommit,
            onFirstInteractiveFrame: onFirstInteractiveFrame,
            onRenderFailure: onRenderFailure
        )
    }

    var body: some View {
        GeometryReader { proxy in
            #if os(macOS)
                GhosttyTerminalMacPlatformView(
                    renderSession: renderSession,
                    appearance: appearance,
                    fontSize: fontSize,
                    selectionMode: selectionMode,
                    focusRequestID: focusRequestID,
                    isSurfaceVisible: isSurfaceVisible,
                    targetPointSize: proxy.size,
                    callbacks: callbacks
                )
            #else
                GhosttyTerminalIOSPlatformView(
                    renderSession: renderSession,
                    appearance: appearance,
                    fontSize: fontSize,
                    selectionMode: selectionMode,
                    focusRequestID: focusRequestID,
                    isSurfaceVisible: isSurfaceVisible,
                    targetPointSize: proxy.size,
                    callbacks: callbacks
                )
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
