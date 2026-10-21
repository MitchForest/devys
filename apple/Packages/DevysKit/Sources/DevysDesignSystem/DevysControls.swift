public import SwiftUI

/// Choices sit in an inset track; the selection rises out of it as a white
/// thumb that springs between options.
public struct SegmentedTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<Value>, options: [(value: Value, title: String)]) {
        _selection = selection
        self.options = options
    }

    public var body: some View {
        // Natural width when it fits; otherwise it scrolls. It never widens its container.
        ViewThatFits(in: .horizontal) {
            track
            ScrollView(.horizontal) { track }
                .scrollIndicators(.never)
        }
    }

    private var track: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(DevysMotion.select(reduceMotion: reduceMotion)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(DevysTypography.control)
                        .foregroundStyle(selected ? DevysColors.ink : DevysColors.ink2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(DevysColors.sheet)
                                    .shadow(color: .black.opacity(0.05), radius: 0.5, y: 0.5)
                                    .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fixedSize()
    }
}

/// A removable filter with a count.
public struct FilterChip: View {
    let title: String
    let count: Int
    let onClear: () -> Void

    public init(_ title: String, count: Int, onClear: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.onClear = onClear
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(DevysColors.ink2)
            Text("\(count)").foregroundStyle(DevysColors.indigo).fontWeight(.semibold)
            Button(action: onClear) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(DevysColors.ink3)
                .accessibilityLabel("Clear \(title) filter")
        }
        .font(DevysTypography.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DevysColors.sheet, in: Capsule())
        .devysElevation(.resting)
    }
}

/// The message field: an inset capsule with an optional leading control (who answers), the
/// mic, which dictates into the field, and the aurora button: send, or with an empty field,
/// talk hands-free.
public struct Composer: View {
    let placeholder: String
    @Binding var text: String
    let isEnabled: Bool
    let note: String?
    let volatileText: String
    let isListening: Bool
    let level: Double
    let onSend: () -> Void
    let onMicTap: (() -> Void)?
    let onHandsFree: (() -> Void)?
    let leading: AnyView?

    public init(
        _ placeholder: String,
        text: Binding<String>,
        isEnabled: Bool = true,
        note: String? = nil,
        volatileText: String = "",
        isListening: Bool = false,
        level: Double = 0,
        onMicTap: (() -> Void)? = nil,
        onHandsFree: (() -> Void)? = nil,
        leading: AnyView? = nil,
        onSend: @escaping () -> Void
    ) {
        self.placeholder = placeholder
        _text = text
        self.isEnabled = isEnabled
        self.note = note
        self.volatileText = volatileText
        self.isListening = isListening
        self.level = level
        self.onMicTap = onMicTap
        self.onHandsFree = onHandsFree
        self.leading = leading
        self.onSend = onSend
    }

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isListening, !volatileText.isEmpty {
                Text(volatileText)
                    .font(DevysTypography.body)
                    .foregroundStyle(DevysColors.ink3)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .transition(.opacity)
                    .accessibilityLabel("Hearing: \(volatileText)")
            }
            HStack(spacing: 6) {
                if let leading { leading }
                TextField(isListening ? "Listening…" : placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DevysTypography.body)
                    .lineLimit(1...6)
                    .disabled(!isEnabled)
                    .onSubmit(onSend)
                if let onMicTap {
                    MicButton(isListening: isListening, level: level, dictate: onMicTap)
                }
                // An empty field offers talking instead of sending, as in ChatGPT.
                if isEmpty, let onHandsFree {
                    AuroraButton(symbol: "waveform", action: onHandsFree)
                        .disabled(!isEnabled)
                        .help("Talk hands-free: speak, hear the answer, keep talking")
                        .accessibilityLabel("Talk hands-free")
                } else {
                    AuroraButton(symbol: "arrow.up", action: onSend)
                        .disabled(!isEnabled || isEmpty)
                        .opacity(isEnabled && !isEmpty ? 1 : 0.4)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel("Send")
                }
            }
            .padding(.leading, leading == nil ? 14 : 5)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .background(DevysColors.sheetTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isListening ? DevysColors.indigo.opacity(0.45) : .clear, lineWidth: 1.5)
            }
            if let note {
                Text(note).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).padding(.horizontal, 6)
            }
        }
        .animation(DevysMotion.quick, value: isListening)
        .animation(DevysMotion.quick, value: volatileText)
    }
}

/// The round aurora button at the end of the field.
private struct AuroraButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background { Aurora().clipShape(Circle()) }
        }
        .buttonStyle(.plain)
    }
}

/// The mic: tap to dictate into the field (or stop); the words stay there to edit.
private struct MicButton: View {
    let isListening: Bool
    let level: Double
    let dictate: () -> Void

    var body: some View {
        Button(action: dictate) {
            Image(systemName: isListening ? "mic.fill" : "mic")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isListening ? DevysColors.indigo : DevysColors.ink2)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(DevysColors.indigo.opacity(isListening ? 0.12 + level * 0.35 : 0))
                        .scaleEffect(isListening ? 1 + level * 0.5 : 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.1), value: level)
        .help(isListening ? "Stop dictating" : "Dictate")
        .accessibilityLabel(isListening ? "Stop dictating" : "Dictate")
    }
}

/// Business identity in the rail and switcher.
public struct BusinessTile: View {
    public enum Tint: String, Sendable, CaseIterable {
        case blue, orange, green, purple, pink
    }

    let initial: String
    let tint: Tint
    let size: CGFloat

    public init(_ initial: String, tint: Tint, size: CGFloat = 36) {
        self.initial = initial
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
    }

    private var colors: [Color] {
        let (light, deep) = Self.colors(for: tint)
        return [light, deep]
    }

    /// The tile's gradient, from its light corner to its deep one.
    public static func colors(for tint: Tint) -> (light: Color, deep: Color) {
        switch tint {
        case .blue: (Color(light: 0x5A89F5, dark: 0x5A89F5), Color(light: 0x2F55C9, dark: 0x2F55C9))
        case .orange: (Color(light: 0xF59A58, dark: 0xF59A58), Color(light: 0xD9603A, dark: 0xD9603A))
        case .green: (Color(light: 0x4CC27E, dark: 0x4CC27E), Color(light: 0x23864D, dark: 0x23864D))
        case .purple: (Color(light: 0xA77AF0, dark: 0xA77AF0), Color(light: 0x6F45C9, dark: 0x6F45C9))
        case .pink: (Color(light: 0xF27DB2, dark: 0xF27DB2), Color(light: 0xC9457F, dark: 0xC9457F))
        }
    }
}

extension View {
    /// A resting card inside a sheet: tinted fill that lifts to white on hover.
    public func devysCard(padding: CGFloat = DevysSpacing.regular) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

private struct CardModifier: ViewModifier {
    let padding: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if hovering {
                    RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous)
                        .fill(DevysColors.sheet)
                        .devysElevation(.raised)
                } else {
                    RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous)
                        .fill(DevysColors.sheetTint)
                }
            }
            .offset(y: hovering ? -1 : 0)
            .onHover { hovering = $0 }
            .animation(DevysMotion.quick, value: hovering)
    }
}
