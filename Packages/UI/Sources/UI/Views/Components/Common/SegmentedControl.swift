// SegmentedControl.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A 2-4 option selector with a sliding indicator.
///
/// The active segment gets an accent-muted background pill that slides
/// between options using the signature spring. Inactive segments show
/// secondary text that transitions to primary on selection.
public struct SegmentedControl: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let options: [String]
    @Binding private var selectedIndex: Int

    @Namespace private var segmentNamespace

    public init(options: [String], selectedIndex: Binding<Int>) {
        self.options = options
        self._selectedIndex = selectedIndex
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                segmentButton(option, index: index)
            }
        }
        .frame(height: layout.buttonHeight)
        .background(theme.card, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                .strokeBorder(theme.border, lineWidth: Spacing.borderWidth)
        )
    }

    // MARK: - Segment Button

    @ViewBuilder
    private func segmentButton(_ title: String, index: Int) -> some View {
        let isSelected = index == selectedIndex

        Button {
            withAnimation(Animations.spring) {
                selectedIndex = index
            }
        } label: {
            Text(title)
                .font(Typography.label)
                .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Spacing.space2)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                            .fill(theme.accentMuted)
                            .matchedGeometryEffect(
                                id: "segment_indicator",
                                in: segmentNamespace
                            )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Segmented Control") {
    struct PreviewWrapper: View {
        @State private var selected2 = 0
        @State private var selected3 = 1
        @State private var selected4 = 2

        var body: some View {
            VStack(spacing: Spacing.space6) {
                VStack(alignment: .leading, spacing: Spacing.space2) {
                    Text("2 options")
                        .font(Typography.caption)
                        .foregroundStyle(Color(hex: "#9E978C"))
                    SegmentedControl(
                        options: ["Editor", "Preview"],
                        selectedIndex: $selected2
                    )
                    .frame(width: 240)
                }

                VStack(alignment: .leading, spacing: Spacing.space2) {
                    Text("3 options")
                        .font(Typography.caption)
                        .foregroundStyle(Color(hex: "#9E978C"))
                    SegmentedControl(
                        options: ["Code", "Split", "Design"],
                        selectedIndex: $selected3
                    )
                    .frame(width: 300)
                }

                VStack(alignment: .leading, spacing: Spacing.space2) {
                    Text("4 options")
                        .font(Typography.caption)
                        .foregroundStyle(Color(hex: "#9E978C"))
                    SegmentedControl(
                        options: ["All", "Modified", "Staged", "Untracked"],
                        selectedIndex: $selected4
                    )
                    .frame(width: 400)
                }
            }
            .padding(24)
            .background(Color(hex: "#121110"))
            .environment(\.theme, Theme(isDark: true))
            .environment(\.densityLayout, DensityLayout(.comfortable))
        }
    }

    return PreviewWrapper()
}
