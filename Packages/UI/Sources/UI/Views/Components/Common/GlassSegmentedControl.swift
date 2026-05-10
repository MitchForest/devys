// GlassSegmentedControl.swift
// Devys Design System
//
// A value-typed two-or-more-option selector designed for glass surfaces.
// Mirrors the API of `SegmentedControl` but renders against `liquidGlassSurface`
// instead of `theme.card`, so it sits cleanly on top of the window vibrancy
// the editor / diff / terminal surfaces share.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A 2–4 option selector designed for glass-backed surfaces.
///
/// Use this in tabs that float on top of the window's vibrancy (the diff
/// tab, the file tab toolbar, the markdown reader header). The control is
/// generic over the selection value so callers can bind to enums and other
/// `Hashable` types directly without an index conversion.
public struct GlassSegmentedControl<Value: Hashable>: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let options: [Option]
    @Binding private var selection: Value

    @Namespace private var indicatorNamespace

    public init(selection: Binding<Value>, options: [Option]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .frame(height: layout.buttonHeight)
        .padding(2)
        .liquidGlassSurface()
    }

    @ViewBuilder
    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection

        Button {
            withAnimation(Animations.spring) {
                selection = option.value
            }
        } label: {
            HStack(spacing: Spacing.tight) {
                if let symbol = option.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(option.label)
                    .font(Typography.label)
            }
            .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Spacing.normal)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Spacing.radius - 2, style: .continuous)
                        .fill(theme.accentMuted)
                        .matchedGeometryEffect(
                            id: "glass_segment_indicator",
                            in: indicatorNamespace
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

public extension GlassSegmentedControl {
    struct Option: Identifiable {
        public let id: AnyHashable
        public let value: Value
        public let label: String
        public let symbol: String?

        public init(value: Value, label: String, symbol: String? = nil) {
            self.id = AnyHashable(value)
            self.value = value
            self.label = label
            self.symbol = symbol
        }
    }
}

#Preview("GlassSegmentedControl") {
    struct Wrapper: View {
        enum Mode: Hashable { case unified, split }

        @State private var mode: Mode = .unified

        var body: some View {
            VStack(spacing: Spacing.relaxed) {
                GlassSegmentedControl(
                    selection: $mode,
                    options: [
                        .init(value: .unified, label: "Unified", symbol: "rectangle"),
                        .init(value: .split,   label: "Split",   symbol: "rectangle.split.2x1")
                    ]
                )
                .frame(width: 200)
            }
            .padding(40)
            .background(Color(hex: "#121110"))
            .environment(\.theme, Theme(isDark: true))
            .environment(\.densityLayout, DensityLayout(.compact))
        }
    }

    return Wrapper()
}
