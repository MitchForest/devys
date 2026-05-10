// InputChip.swift
// Devys Design System — Dia-modeled
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Inline chip for tokens inserted into a composer or input field.
///
/// Single-row layout: leading view (SF Symbol or thumbnail), title with
/// middle truncation, optional inline subtitle with tail truncation, optional
/// trailing remove affordance. Lives on top of a `.card` surface using the
/// standard radius — no shadow, no capsule.
public struct InputChip: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    private let leading: AnyView
    private let title: String
    private let subtitle: String?
    private let chipAccessibilityLabel: String?
    private let onTap: (() -> Void)?
    private let onRemove: (() -> Void)?

    /// SF Symbol leading.
    public init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        accessibilityLabel: String? = nil,
        onTap: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.init(
            leading: { InputChipSymbolLeading(systemImage: systemImage) },
            title: title,
            subtitle: subtitle,
            accessibilityLabel: accessibilityLabel,
            onTap: onTap,
            onRemove: onRemove
        )
    }

    /// Custom leading view (e.g. an image thumbnail). The leading view is
    /// rendered inside a 20×20 frame and clipped to the inner radius.
    public init<Leading: View>(
        @ViewBuilder leading: () -> Leading,
        title: String,
        subtitle: String? = nil,
        accessibilityLabel: String? = nil,
        onTap: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.leading = AnyView(leading())
        self.title = title
        self.subtitle = subtitle
        self.chipAccessibilityLabel = accessibilityLabel
        self.onTap = onTap
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: 0) {
            labelRegion
            if let onRemove {
                removeButton(onRemove)
                    .padding(.leading, Spacing.tight)
            }
        }
        .padding(.leading, Spacing.normal)
        .padding(.trailing, onRemove == nil ? Spacing.normal : Spacing.tight)
        .padding(.vertical, Spacing.tight)
        .frame(maxWidth: InputChipLayout.maxWidth, alignment: .leading)
        .background(backgroundFill, in: shape)
        .overlay {
            shape.strokeBorder(theme.border, lineWidth: Spacing.borderWidth)
        }
        .contentShape(shape)
        .onHover { hovering in
            withAnimation(Animations.micro) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chipAccessibilityLabel ?? combinedAccessibilityLabel)
    }

    @ViewBuilder
    private var labelRegion: some View {
        if let onTap {
            Button(action: onTap) {
                labelRow
            }
            .buttonStyle(.plain)
        } else {
            labelRow
        }
    }

    private var labelRow: some View {
        HStack(spacing: Spacing.tight) {
            leading
                .frame(width: Spacing.iconLg, height: Spacing.iconLg)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: Spacing.innerRadius(padding: Spacing.tight),
                        style: .continuous
                    )
                )
                .foregroundStyle(isHovered ? theme.text : theme.textSecondary)
                .layoutPriority(1)

            ViewThatFits(in: .horizontal) {
                titleAndSubtitle
                titleOnly
            }
        }
    }

    private var titleAndSubtitle: some View {
        HStack(spacing: Spacing.tight) {
            Text(title)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .truncationMode(.middle)

            if let subtitle, !subtitle.isEmpty {
                Text("·")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textTertiary)
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var titleOnly: some View {
        Text(title)
            .font(Typography.caption.weight(.semibold))
            .foregroundStyle(theme.text)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        InputChipRemoveButton(title: title, action: action)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
    }

    private var backgroundFill: Color {
        isHovered ? theme.text.opacity(0.10) : theme.cardHover
    }

    private var combinedAccessibilityLabel: String {
        if let subtitle, !subtitle.isEmpty {
            return "\(title), \(subtitle)"
        }
        return title
    }
}

// MARK: - Layout

private enum InputChipLayout {
    static let maxWidth: CGFloat = 240
}

// MARK: - Symbol Leading

private struct InputChipSymbolLeading: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(Typography.caption.weight(.medium))
    }
}

// MARK: - Remove Button

private struct InputChipRemoveButton: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Typography.micro.weight(.bold))
                .foregroundStyle(isHovered ? theme.text : theme.textTertiary)
                .frame(width: Spacing.iconLg, height: Spacing.iconLg)
                .background(
                    backgroundFill,
                    in: RoundedRectangle(
                        cornerRadius: Spacing.innerRadius(padding: Spacing.tight),
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(title)")
        .help("Remove \(title)")
        .onHover { hovering in
            withAnimation(Animations.micro) {
                isHovered = hovering
            }
        }
    }

    private var backgroundFill: Color {
        isHovered ? theme.border.opacity(0.6) : .clear
    }
}

// MARK: - Previews

#Preview("InputChip") {
    let theme = Theme(isDark: true)
    return VStack(alignment: .leading, spacing: Spacing.space4) {
        Text("Symbol leading")
            .font(Typography.micro)
            .foregroundStyle(theme.textTertiary)
        VStack(alignment: .leading, spacing: Spacing.space2) {
            HStack(spacing: Spacing.normal) {
                InputChip(
                    systemImage: "doc.text",
                    title: "ContentView.swift",
                    subtitle: "12 KB",
                    onTap: {},
                    onRemove: {}
                )
                InputChip(
                    systemImage: "folder",
                    title: "Packages",
                    subtitle: "42 items",
                    onTap: {},
                    onRemove: {}
                )
                InputChip(
                    systemImage: "doc.on.clipboard",
                    title: "Paste · 12 lines",
                    subtitle: "import SwiftUI; struct Foo: View { ... }",
                    onTap: {},
                    onRemove: {}
                )
            }
            HStack(spacing: Spacing.normal) {
                InputChip(
                    systemImage: "doc.text",
                    title: "extremely-long-filename-that-should-middle-truncate.swift",
                    subtitle: "43 KB",
                    onRemove: {}
                )
                InputChip(
                    systemImage: "plus.forwardslash.minus",
                    title: "Diff · 3 hunks"
                )
            }
        }
        .padding(Spacing.comfortable)
        .background(theme.card, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))

        Text("Custom leading (thumbnail-shaped)")
            .font(Typography.micro)
            .foregroundStyle(theme.textTertiary)
        HStack(spacing: Spacing.normal) {
            InputChip(
                leading: {
                    Rectangle()
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                },
                title: "hero.png",
                subtitle: "1920×1080",
                onTap: {},
                onRemove: {}
            )
            InputChip(
                leading: {
                    ZStack {
                        Rectangle().fill(.gray.opacity(0.4))
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                },
                title: "demo.mov",
                subtitle: "4.1 MB",
                onRemove: {}
            )
        }
        .padding(Spacing.comfortable)
        .background(theme.card, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
    }
    .padding(Spacing.space6)
    .background(theme.base)
    .environment(\.theme, theme)
}
