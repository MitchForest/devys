// AssistantComposerView.swift
// Phase 1 assistant composer.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import SwiftUI
import UI

struct AssistantComposerView: View {
    @Environment(\.devysTheme) private var theme

    let mode: AssistantMode
    let onSend: (String) -> Void

    @State private var text = ""
    @State private var isFocused = false
    @State private var showRipple = false
    @State private var isThinking = false
    @State private var isListening = false
    @State private var composerScale: CGFloat = 1

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            HStack(spacing: DevysSpacing.space2) {
                Circle()
                    .fill(mode.accent)
                    .frame(width: 7, height: 7)

                if isThinking {
                    AssistantThinkingDots(tint: mode.accent)
                } else if isListening {
                    Text("listening...")
                        .font(DevysTypography.caption)
                        .foregroundStyle(theme.textSecondary)
                } else {
                    Text("ready")
                        .font(DevysTypography.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            }

            HStack(alignment: .bottom, spacing: DevysSpacing.space2) {
                composerField

                Button {
                    startSpeechToTextStub()
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: DevysSpacing.iconMd))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start voice input")
                .accessibilityHint("Start speech-to-text input")

                ZStack {
                    if canSend {
                        Button {
                            send()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(mode.accent)
                                .frame(width: 30, height: 30)
                                .background(theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Send message")
                        .accessibilityHint("Send assistant prompt")
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }

                    if showRipple {
                        Circle()
                            .fill(mode.accent.opacity(0.2))
                            .frame(width: 20, height: 20)
                            .scaleEffect(showRipple ? 1.5 : 1.0)
                            .opacity(showRipple ? 0.0 : 0.3)
                            .animation(DevysAnimation.slow, value: showRipple)
                    }
                }
                .frame(width: 30, height: 30)
            }
        }
        .animation(DevysAnimation.default, value: canSend)
    }

    private var composerField: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("ask anything...")
                    .font(DevysTypography.body)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, DevysSpacing.space3)
                    .padding(.vertical, DevysSpacing.space2)
                    .allowsHitTesting(false)
            }

            AssistantComposerTextView(
                text: $text,
                onSubmit: send
            ) { focused in
                    withAnimation(DevysAnimation.focus) {
                        isFocused = focused
                    }
            }
            .frame(minHeight: 38, maxHeight: 92)
            .padding(.horizontal, DevysSpacing.space2)
            .padding(.vertical, DevysSpacing.space1)
        }
        .background(isFocused ? theme.elevated : theme.surface)
        .scaleEffect(composerScale)
        .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusLg))
        .overlay {
            RoundedRectangle(cornerRadius: DevysSpacing.radiusLg)
                .strokeBorder(
                    isFocused ? mode.accent.opacity(0.2) : theme.borderSubtle,
                    lineWidth: 1
                )
        }
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isListening = false
        onSend(trimmed)
        text = ""

        withAnimation(DevysAnimation.fast) {
            composerScale = 0.97
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(DevysAnimation.fast) {
                composerScale = 1
            }
        }

        showRipple = false
        showRipple = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            showRipple = false
        }

        isThinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isThinking = false
        }
    }

    private func startSpeechToTextStub() {
        guard !isListening else { return }

        NSSound.beep()
        withAnimation(DevysAnimation.focus) {
            isListening = true
            isFocused = true
        }

        let stub = sttStubText(for: mode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            if text.isEmpty {
                text = stub
            } else {
                text += " \(stub)"
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(DevysAnimation.focus) {
                isListening = false
            }
        }
    }

    private func sttStubText(for mode: AssistantMode) -> String {
        switch mode {
        case .calendar:
            return "Summarize my next meeting."
        case .gmail:
            return "Draft a reply for my top unread email."
        case .gchat:
            return "Catch me up on unread chat mentions."
        }
    }
}

private struct AssistantThinkingDots: View {
    let tint: Color
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            dot(index: 0)
            dot(index: 1)
            dot(index: 2)
        }
        .onAppear {
            phase = true
        }
    }

    private func dot(index: Int) -> some View {
        Circle()
            .fill(tint)
            .frame(width: 5, height: 5)
            .scaleEffect(phase ? 1.3 : 1.0)
            .animation(
                DevysAnimation.default
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.1),
                value: phase
            )
    }
}

private struct AssistantComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onFocusChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let textView = SubmitTextView(frame: .zero)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 2, height: 8)
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = true
        textView.onSubmit = onSubmit
        textView.focusChanged = onFocusChanged
        textView.delegate = context.coordinator
        textView.string = text
        textView.setAccessibilityLabel("Assistant composer")
        textView.setAccessibilityHelp("Enter to send. Shift plus Enter for newline.")

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: AssistantComposerTextView

        init(_ parent: AssistantComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var focusChanged: ((Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36
        let hasShift = event.modifierFlags.contains(.shift)
        if isReturn && !hasShift {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            focusChanged?(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            focusChanged?(false)
        }
        return resigned
    }
}
