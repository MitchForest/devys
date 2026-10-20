public import DevysCharacter
public import SwiftUI

/// Any look an employee, business or person can wear.
public enum PortraitSource: Equatable, Sendable {
    case face(AvatarSpec)
    case emoji(String, tint: BusinessTile.Tint)
    case photo(Data)
    case initials(String, tint: BusinessTile.Tint)
}

/// Renders a look at any size. The Face shows mood with its eyes; emoji,
/// photos and initials show it with a ring (working) or a dot (waiting, oops).
public struct Portrait: View {
    let source: PortraitSource
    let size: CGFloat
    let mood: BotMood
    let label: String?
    let isAnimated: Bool

    public init(_ source: PortraitSource, size: CGFloat, mood: BotMood = .idle, label: String? = nil, isAnimated: Bool = true) {
        self.source = source
        self.size = size
        self.mood = mood
        self.label = label
        self.isAnimated = isAnimated
    }

    public var body: some View {
        switch source {
        case .face(let spec):
            DevysAvatar(spec, size: size, mood: mood, label: label, isAnimated: isAnimated)
        case .emoji(let emoji, let tint):
            tile(tint: tint) { Text(emoji).font(.system(size: size * 0.56)) }
        case .initials(let text, let tint):
            BusinessTile(text, tint: tint, size: size)
                .overlay { MoodMark(mood: mood, size: size, radius: size * 0.3, animated: isAnimated) }
                .modifier(PortraitLabel(label: label, mood: mood))
        case .photo(let data):
            Group {
                if let image = PlatformImage.decode(data) {
                    image.resizable().scaledToFill()
                } else {
                    DevysColors.sheetTint
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(DevysColors.hairline)
            }
            .overlay { MoodMark(mood: mood, size: size, radius: size * 0.3, animated: isAnimated) }
            .modifier(PortraitLabel(label: label, mood: mood))
        }
    }

    private func tile(tint: BusinessTile.Tint, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: size, height: size)
            .background(DevysColors.sheet, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(BusinessTile.colors(for: tint).first!.opacity(0.14))
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(DevysColors.hairline)
            }
            .overlay { MoodMark(mood: mood, size: size, radius: size * 0.3, animated: isAnimated) }
            .modifier(PortraitLabel(label: label, mood: mood))
    }
}

private struct PortraitLabel: ViewModifier {
    let label: String?
    let mood: BotMood

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(label == nil)
            .accessibilityLabel(Text(label.map { "\($0), \(mood.accessibilityDescription)" } ?? ""))
    }
}

/// Mood for looks without eyes: a turning ring while working, a dot when waiting.
private struct MoodMark: View {
    let mood: BotMood
    let size: CGFloat
    let radius: CGFloat
    let animated: Bool
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch mood {
        case .working, .thinking:
            RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                .strokeBorder(DevysColors.indigo, style: StrokeStyle(lineWidth: max(1.5, size * 0.05), dash: [size * 0.12, size * 0.08], dashPhase: turning ? size : 0))
                .padding(-3)
                .onAppear {
                    guard animated, !reduceMotion else { return }
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { turning = true }
                }
        case .waiting, .oops:
            Circle()
                .fill(mood == .waiting ? DevysColors.amber : DevysColors.red)
                .frame(width: max(7, size * 0.26), height: max(7, size * 0.26))
                .overlay { Circle().strokeBorder(DevysColors.sheet, lineWidth: max(1.5, size * 0.05)) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: size * 0.08, y: size * 0.08)
        default:
            EmptyView()
        }
    }
}

enum PlatformImage {
    static func decode(_ data: Data) -> Image? {
        #if os(macOS)
            NSImage(data: data).map { Image(nsImage: $0) }
        #else
            UIImage(data: data).map { Image(uiImage: $0) }
        #endif
    }
}
