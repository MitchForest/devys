import SwiftUI
import UI
import UIKit

struct IOSAssistantComposerView: View {
    @Environment(\.devysTheme) private var theme

    let mode: IOSAssistantMode
    let onSend: (String) -> Void

    @State private var text = ""
    @State private var isThinking = false
    @State private var isListening = false
    @State private var isFocused = false
    @State private var composerScale: CGFloat = 1
    @State private var showRipple = false
    @FocusState private var isTextFieldFocused: Bool

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
                    IOSAssistantThinkingDots(tint: mode.accent)
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
                TextField("ask anything...", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .font(DevysTypography.body)
                    .foregroundStyle(theme.text)
                    .focused($isTextFieldFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        send()
                    }
                    .padding(.horizontal, DevysSpacing.space3)
                    .padding(.vertical, DevysSpacing.space2)
                    .background(isFocused ? theme.elevated : theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusLg))
                    .overlay {
                        RoundedRectangle(cornerRadius: DevysSpacing.radiusLg)
                            .strokeBorder(isFocused ? mode.accent.opacity(0.2) : theme.borderSubtle, lineWidth: 1)
                    }
                    .scaleEffect(composerScale)
                    .accessibilityLabel("Assistant composer")
                    .accessibilityHint("Enter to send")

                Button {
                    startSpeechToTextStub()
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: DevysSpacing.iconMd))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start voice input")
                .accessibilityHint("Insert a sample transcription")

                if canSend {
                    ZStack {
                        Button {
                            send()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(mode.accent)
                                .frame(width: 32, height: 32)
                                .background(theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Send message")
                        .accessibilityHint("Send assistant prompt")

                        if showRipple {
                            Circle()
                                .fill(mode.accent.opacity(0.2))
                                .frame(width: 24, height: 24)
                                .scaleEffect(showRipple ? 1.5 : 1.0)
                                .opacity(showRipple ? 0.0 : 0.3)
                                .animation(DevysAnimation.slow, value: showRipple)
                        }
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
        .animation(DevysAnimation.default, value: canSend)
        .onChange(of: isTextFieldFocused) { _, newValue in
            withAnimation(DevysAnimation.focus) {
                isFocused = newValue
            }
        }
    }

    private func startSpeechToTextStub() {
        guard !isListening else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(DevysAnimation.focus) {
            isListening = true
        }
        isTextFieldFocused = true

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

    private func sttStubText(for mode: IOSAssistantMode) -> String {
        switch mode {
        case .calendar:
            return "Summarize my next meeting."
        case .gmail:
            return "Draft a reply for my top unread email."
        case .gchat:
            return "Catch me up on unread chat mentions."
        }
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
}

private struct IOSAssistantThinkingDots: View {
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
