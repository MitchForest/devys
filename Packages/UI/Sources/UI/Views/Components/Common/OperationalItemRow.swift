// OperationalItemRow.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

struct OperationalItemRow: View {
    @Environment(\.theme) private var theme

    private let icon: String
    private let title: String
    private let subtitle: String?
    private let status: StatusDot.Status
    private let pills: [Pill]
    private let accessories: [Accessory]
    private let onTap: (() -> Void)?

    @State private var isHovered = false

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        status: StatusDot.Status,
        pills: [Pill] = [],
        accessories: [Accessory] = [],
        onTap: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.pills = pills
        self.accessories = accessories
        self.onTap = onTap
    }

    var body: some View {
        rowContent
            .contentShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            .onTapGesture {
                onTap?()
            }
        .onHover { hovering in
            withAnimation(Animations.micro) {
                isHovered = hovering
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: Spacing.space2) {
            HStack(alignment: .center, spacing: Spacing.space1) {
                DevysIcon(icon, size: 14, weight: .semibold)
                    .foregroundStyle(theme.accent)
                    .frame(width: 14, height: 14)

                StatusDot(status, size: 6)
            }
            .padding(.top, 3)
            .frame(width: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Spacing.space2)

            if !pills.isEmpty || !accessories.isEmpty {
                VStack(alignment: .trailing, spacing: Spacing.space1) {
                    if !pills.isEmpty {
                        ForEach(pills) { pill in
                            pillView(pill)
                        }
                    }

                    if !accessories.isEmpty {
                        HStack(spacing: Spacing.space1) {
                            ForEach(accessories) { accessory in
                                IconButton(
                                    accessory.icon,
                                    style: .ghost,
                                    tone: accessory.tone == .destructive ? .destructive : .standard,
                                    size: .sm,
                                    accessibilityLabel: accessory.accessibilityLabel,
                                    action: accessory.action
                                )
                            }
                        }
                        .opacity(isHovered ? 1 : 0)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.space3)
        .padding(.vertical, Spacing.space2)
        .background(
            isHovered ? theme.hover : .clear,
            in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
    }

    @ViewBuilder
    private func pillView(_ pill: Pill) -> some View {
        switch pill.tone {
        case .neutral:
            Chip(.tag(pill.title))
        case .accent:
            statusPill(pill.title, color: theme.accent)
        case .success:
            statusPill(pill.title, color: theme.success)
        case .warning:
            statusPill(pill.title, color: theme.warning)
        case .error:
            statusPill(pill.title, color: theme.error)
        }
    }

    private func statusPill(
        _ title: String,
        color: Color
    ) -> some View {
        Chip(.status(title, color))
    }
}

extension OperationalItemRow {
    struct Accessory: Identifiable {
        enum Tone: String, Sendable {
            case standard
            case destructive
        }

        let id = UUID()
        let icon: String
        let accessibilityLabel: String
        let tone: Tone
        let action: () -> Void

        init(
            icon: String,
            accessibilityLabel: String,
            tone: Tone = .standard,
            action: @escaping () -> Void
        ) {
            self.icon = icon
            self.accessibilityLabel = accessibilityLabel
            self.tone = tone
            self.action = action
        }
    }

    struct Pill: Equatable, Sendable, Identifiable {
        enum Tone: String, Equatable, Sendable {
            case neutral
            case accent
            case success
            case warning
            case error
        }

        let title: String
        let tone: Tone

        init(
            _ title: String,
            tone: Tone = .neutral
        ) {
            self.title = title
            self.tone = tone
        }

        var id: String {
            "\(tone.rawValue):\(title)"
        }
    }
}

#Preview("Operational Item Rows") {
    VStack(spacing: 0) {
        OperationalItemRow(
            icon: DevysIconName.codex,
            title: "Codex",
            subtitle: "Waiting for input",
            status: .running,
            pills: [
                .init("Waiting", tone: .warning),
                .init("Open")
            ]
        )

        OperationalItemRow(
            icon: "server.rack",
            title: "API",
            subtitle: "localhost:3000",
            status: .error,
            pills: [
                .init("Attention", tone: .error),
                .init("Minimized")
            ]
        )
    }
    .padding(.vertical, Spacing.space2)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
