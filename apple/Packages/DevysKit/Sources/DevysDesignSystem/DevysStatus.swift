public import SwiftUI

/// Outcome status as an icon plus colored text on a white pill. Never a filled
/// block of color. Uncertain work is `checking`, never shown as done.
public struct StatusChip: View {
    public enum Tone: Sendable, Equatable {
        case needsYou, inProgress, done, failed, expired, checking, waiting
    }

    public enum Size: Sendable {
        /// Lists and cards.
        case regular
        /// Sidebar rows and other dense places.
        case small
    }

    let tone: Tone
    let text: String
    let size: Size

    public init(_ text: String, tone: Tone, size: Size = .regular) {
        self.text = text
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        HStack(spacing: size == .small ? 4 : 6) {
            StatusGlyph(tone: tone, diameter: size == .small ? 12 : 16)
            Text(text)
        }
        .font(size == .small ? .system(size: 10.5, weight: .semibold) : DevysTypography.caption)
        .foregroundStyle(color)
        .padding(.leading, size == .small ? 3 : 5)
        .padding(.trailing, size == .small ? 7 : 10)
        .padding(.vertical, size == .small ? 2 : 4)
        .background(DevysColors.sheet, in: Capsule())
        .devysElevation(.resting)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var color: Color { tone.color }
}

extension StatusChip.Tone {
    var color: Color {
        switch self {
        case .needsYou: DevysColors.amber
        case .inProgress: DevysColors.indigo
        case .done: DevysColors.green
        case .failed: DevysColors.red
        case .expired, .checking, .waiting: DevysColors.gray
        }
    }
}

private struct StatusGlyph: View {
    let tone: StatusChip.Tone
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        Group {
            switch tone {
            case .inProgress:
                Circle()
                    .strokeBorder(tone.color, style: StrokeStyle(lineWidth: 1.6, dash: [2.6, 2]))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { spinning = true }
                    }
            case .done:
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(tone.color)
                    .overlay { symbol("checkmark") }
            default:
                Circle().fill(tone.color).overlay { symbol(glyph) }
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var glyph: String {
        switch tone {
        case .needsYou: "exclamationmark"
        case .failed: "xmark"
        case .expired, .waiting: "clock"
        case .checking: "ellipsis"
        case .inProgress, .done: ""
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: diameter * 0.5, weight: .heavy))
            .foregroundStyle(.white)
    }
}

/// Dashed means not real yet: a draft or a slot to fill.
public struct DashedTag: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(DevysTypography.caption)
            .foregroundStyle(DevysColors.ink2)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .overlay { Capsule().strokeBorder(DevysColors.ink3, style: StrokeStyle(lineWidth: 1.2, dash: [3.5, 2.5])) }
            .fixedSize()
    }
}

public struct LiveTag: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 5) {
            Circle().fill(DevysColors.green).frame(width: 6, height: 6)
            Text("Live")
        }
        .font(DevysTypography.caption)
        .foregroundStyle(DevysColors.green)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(DevysColors.greenTint, in: Capsule())
        .fixedSize()
        .accessibilityLabel("Live data")
    }
}

/// A small section label with an optional count.
public struct SectionHeader: View {
    let title: String
    let count: Int?

    public init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(DevysTypography.heading.weight(.semibold)).foregroundStyle(DevysColors.ink)
            if let count { Text("\(count)").font(DevysTypography.body).foregroundStyle(DevysColors.ink3) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
