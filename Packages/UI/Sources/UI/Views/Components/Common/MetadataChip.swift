// MetadataChip.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A compact two-line label with a title caption and a value row.
///
/// Use for metadata rows such as `Host / 100.64.0.10`, `Branch / main`,
/// or `PWD / ~/Code/devys` where a single-line `Chip` is not enough.
/// Lives on top of `theme.overlay` with the standard radius.
public struct MetadataChip: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.micro.weight(.semibold))
                .foregroundStyle(theme.textTertiary)
            Text(value)
                .font(Typography.caption)
                .foregroundStyle(theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.space3)
        .padding(.vertical, Spacing.space2)
        .background(theme.overlay, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
    }
}

#Preview("Metadata Chips") {
    HStack(spacing: Spacing.space2) {
        MetadataChip(title: "Host", value: "mac-mini")
        MetadataChip(title: "Branch", value: "feat/ssh")
        MetadataChip(title: "Port", value: "22")
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
