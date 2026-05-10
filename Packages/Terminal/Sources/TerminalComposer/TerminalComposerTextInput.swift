import SwiftUI
import UI

#if os(macOS)
import AppKit
#endif

struct TerminalComposerTextInput: View {
    @Environment(\.theme) private var theme
    #if !os(macOS)
    @FocusState private var isEditorFocused: Bool
    #endif

    @Binding var text: String
    var isFocused: Bool
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var onFocus: () -> Void
    var onSubmit: () -> Void
    var onNewline: () -> Void
    var onEscape: () -> Void

    private static let nominalLineHeight: CGFloat = 18

    private var resolvedHeight: CGFloat {
        let lines = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
        let raw = CGFloat(lines) * Self.nominalLineHeight + 8
        return min(max(raw, minHeight), maxHeight)
    }

    var body: some View {
        #if os(macOS)
        TerminalComposerMacTextInput(
            text: $text,
            isFocused: isFocused,
            onFocus: onFocus,
            onSubmit: onSubmit,
            onNewline: onNewline,
            onEscape: onEscape
        )
        .frame(height: resolvedHeight)
        #else
        TextEditor(text: $text)
            .font(Typography.body)
            .foregroundStyle(theme.text)
            .tint(theme.text)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .focused($isEditorFocused)
            .frame(height: resolvedHeight)
            #if os(macOS)
            .background(
                TerminalComposerTextInputKeyMonitor(
                    isActive: isEditorFocused,
                    onSubmit: onSubmit,
                    onNewline: onNewline,
                    onEscape: onEscape
                )
            )
            #endif
            .onChange(of: isFocused, initial: true) { _, shouldFocus in
                guard isEditorFocused != shouldFocus else { return }
                isEditorFocused = shouldFocus
            }
            .onChange(of: isEditorFocused) { _, focused in
                if focused {
                    onFocus()
                }
            }
            #if os(macOS)
            .onExitCommand(perform: onEscape)
            #endif
        #endif
    }
}

#if os(macOS)
private struct TerminalComposerMacTextInput: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var onFocus: () -> Void
    var onSubmit: () -> Void
    var onNewline: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = TerminalComposerNSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 1)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.onFocus = onFocus
        textView.onSubmit = onSubmit
        textView.onNewline = onNewline
        textView.onEscape = onEscape

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? TerminalComposerNSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.onFocus = onFocus
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onNewline = onNewline
        context.coordinator.onEscape = onEscape
        textView.onFocus = onFocus
        textView.onSubmit = onSubmit
        textView.onNewline = onNewline
        textView.onEscape = onEscape

        if textView.string != text {
            context.coordinator.isProgrammaticUpdate = true
            textView.string = text
            context.coordinator.isProgrammaticUpdate = false
        }

        guard isFocused else { return }

        if textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onFocus: onFocus,
            onSubmit: onSubmit,
            onNewline: onNewline,
            onEscape: onEscape
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onFocus: () -> Void
        var onSubmit: () -> Void
        var onNewline: () -> Void
        var onEscape: () -> Void
        var isProgrammaticUpdate = false

        init(
            text: Binding<String>,
            onFocus: @escaping () -> Void,
            onSubmit: @escaping () -> Void,
            onNewline: @escaping () -> Void,
            onEscape: @escaping () -> Void
        ) {
            self.text = text
            self.onFocus = onFocus
            self.onSubmit = onSubmit
            self.onNewline = onNewline
            self.onEscape = onEscape
        }

        func textDidBeginEditing(_ notification: Notification) {
            onFocus()
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let textView = notification.object as? NSTextView
            else { return }
            text.wrappedValue = textView.string
        }
    }
}

private final class TerminalComposerNSTextView: NSTextView {
    var onFocus: () -> Void = {}
    var onSubmit: () -> Void = {}
    var onNewline: () -> Void = {}
    var onEscape: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        onFocus()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 36, 76:
            let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
            guard !modifiers.contains(.control),
                  !modifiers.contains(.option),
                  !modifiers.contains(.command)
            else {
                super.keyDown(with: event)
                return
            }

            if modifiers.contains(.shift) {
                onNewline()
            } else {
                onSubmit()
            }

        case 53:
            onEscape()

        default:
            super.keyDown(with: event)
        }
    }
}
#endif
