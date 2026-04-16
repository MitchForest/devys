// DesignSystemGallery.swift
// Devys Design System — Component Gallery
//
// Copyright © 2026 Devys. All rights reserved.

#if DEBUG

import SwiftUI

/// Debug-only gallery that renders all design tokens and components.
///
/// Access via the command palette or debug menu.
/// Use for visual regression testing and design system documentation.
public struct DesignSystemGallery: View {
    @State private var isDark = true
    @State private var isCompact = false
    @State private var selectedAccent: AccentColor = .violet

    private var theme: Theme {
        Theme(isDark: isDark, accentColor: selectedAccent)
    }

    private var density: Density {
        isCompact ? .compact : .comfortable
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.space8) {
                header
                modeToggles
                colorTokens
                typographyTokens
                spacingTokens
                buttonShowcase
                chipShowcase
                statusShowcase
                agentColorShowcase
            }
            .padding(Spacing.space8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.base)
        .environment(\.theme, theme)
        .environment(\.densityLayout, DensityLayout(density))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.space2) {
            Text("Design System Gallery")
                .font(Typography.display)
                .foregroundStyle(theme.text)
            let mode = isDark ? "Dark" : "Light"
            let density = isCompact ? "Compact" : "Comfortable"
            Text("Version \(DesignSystem.version) — \(mode) / \(density)")
                .font(Typography.caption)
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: - Mode Toggles

    private var modeToggles: some View {
        HStack(spacing: Spacing.space6) {
            Toggle("Dark mode", isOn: $isDark)
                .toggleStyle(.switch)
            Toggle("Compact", isOn: $isCompact)
                .toggleStyle(.switch)
            Picker("Accent", selection: $selectedAccent) {
                ForEach(AccentColor.allCases, id: \.self) { accent in
                    Text(accent.displayName).tag(accent)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)
        }
        .font(Typography.body)
        .foregroundStyle(theme.text)
    }

    // MARK: - Color Tokens

    private var colorTokens: some View {
        gallerySection("Color Tokens") {
            VStack(alignment: .leading, spacing: Spacing.space4) {
                HStack(spacing: Spacing.space2) {
                    colorSwatch("base", theme.base)
                    colorSwatch("card", theme.card)
                    colorSwatch("overlay", theme.overlay)
                    colorSwatch("hover", theme.hover)
                    colorSwatch("active", theme.active)
                }

                HStack(spacing: Spacing.space2) {
                    colorSwatch("text", theme.text)
                    colorSwatch("secondary", theme.textSecondary)
                    colorSwatch("tertiary", theme.textTertiary)
                }

                HStack(spacing: Spacing.space2) {
                    colorSwatch("accent", theme.accent)
                    colorSwatch("muted", theme.accentMuted)
                    colorSwatch("subtle", theme.accentSubtle)
                }

                HStack(spacing: Spacing.space2) {
                    colorSwatch("success", theme.success)
                    colorSwatch("warning", theme.warning)
                    colorSwatch("error", theme.error)
                    colorSwatch("info", theme.info)
                }
            }
        }
    }

    private func colorSwatch(_ label: String, _ color: Color) -> some View {
        VStack(spacing: Spacing.space1) {
            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                .fill(color)
                .frame(width: 60, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
            Text(label)
                .font(Typography.micro)
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: - Typography Tokens

    private var typographyTokens: some View {
        gallerySection("Typography") {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                Text("Display (24pt Bold)").font(Typography.display).foregroundStyle(theme.text)
                Text("Title (18pt Semibold)").font(Typography.title).foregroundStyle(theme.text)
                Text("Heading (14pt Medium)").font(Typography.heading).foregroundStyle(theme.text)
                Text("Body (13pt Regular)").font(Typography.body).foregroundStyle(theme.text)
                Text("Label (12pt Medium)").font(Typography.label).foregroundStyle(theme.text)
                Text("Caption (11pt Regular)").font(Typography.caption).foregroundStyle(theme.text)
                Text("Micro (10pt Medium)").font(Typography.micro).foregroundStyle(theme.text)
                Separator()
                Text("Code.base (13pt Mono)").font(Typography.Code.base).foregroundStyle(theme.text)
                Text("Code.sm (12pt Mono)").font(Typography.Code.sm).foregroundStyle(theme.text)
                Text("Code.gutter (11pt Mono)").font(Typography.Code.gutter).foregroundStyle(theme.text)
            }
        }
    }

    // MARK: - Spacing Tokens

    private var spacingTokens: some View {
        gallerySection("Corner Radii") {
            HStack(spacing: Spacing.space4) {
                radiusSample("micro (4)", Spacing.radiusMicro)
                radiusSample("radius (12)", Spacing.radius)
                radiusSample("full", Spacing.radiusFull)
            }
        }
    }

    private func radiusSample(_ label: String, _ radius: CGFloat) -> some View {
        VStack(spacing: Spacing.space1) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.card)
                .frame(width: 48, height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
            Text(label)
                .font(Typography.micro)
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: - Buttons

    private var buttonShowcase: some View {
        gallerySection("Buttons") {
            HStack(spacing: Spacing.space4) {
                ActionButton("Primary", style: .primary) {}
                ActionButton("Ghost", style: .ghost) {}
                ActionButton("Destructive", style: .ghost, tone: .destructive) {}
                ActionButton("Loading", style: .primary, isLoading: true) {}
            }
        }
    }

    // MARK: - Chips

    private var chipShowcase: some View {
        gallerySection("Chips") {
            HStack(spacing: Spacing.space3) {
                Chip(.status("Running", theme.success))
                Chip(.status("Error", theme.error))
                Chip(.status("Waiting", theme.warning))
                Chip(.tag("Swift"))
                Chip(.count(42))
            }
        }
    }

    // MARK: - Status

    private var statusShowcase: some View {
        gallerySection("Status Indicators") {
            HStack(spacing: Spacing.space6) {
                VStack(spacing: Spacing.space1) {
                    StatusDot(.running)
                    Text("Running").font(Typography.micro).foregroundStyle(theme.textTertiary)
                }
                VStack(spacing: Spacing.space1) {
                    StatusDot(.complete)
                    Text("Complete").font(Typography.micro).foregroundStyle(theme.textTertiary)
                }
                VStack(spacing: Spacing.space1) {
                    StatusDot(.error)
                    Text("Error").font(Typography.micro).foregroundStyle(theme.textTertiary)
                }
                VStack(spacing: Spacing.space1) {
                    StatusDot(.idle)
                    Text("Idle").font(Typography.micro).foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    // MARK: - Agent Colors

    private var agentColorShowcase: some View {
        gallerySection("Agent Identity Colors") {
            HStack(spacing: Spacing.space3) {
                ForEach(0..<8, id: \.self) { index in
                    let agent = AgentColor.forIndex(index)
                    VStack(spacing: Spacing.space1) {
                        Circle()
                            .fill(agent.solid)
                            .frame(width: 24, height: 24)
                        Text(agent.displayName)
                            .font(Typography.micro)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Section Helper

    private func gallerySection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            Text(title)
                .font(Typography.heading)
                .foregroundStyle(theme.textSecondary)
            content()
                .padding(Spacing.space4)
                .background(theme.card, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
        }
    }
}

#Preview("Design System Gallery") {
    DesignSystemGallery()
        .frame(width: 900, height: 800)
}

#endif
