// Toggle.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// macOS-style toggle with accent-colored track.
///
/// Use as a ToggleStyle:
/// ```swift
/// Toggle("Dark Mode", isOn: $isDark)
///     .toggleStyle(ThemeToggleStyle())
/// ```
public struct ThemeToggleStyle: ToggleStyle {
    @Environment(\.theme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                    .font(Typography.body)
                    .foregroundStyle(theme.text)
                Spacer()
                switchTrack(isOn: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
    }

    private func switchTrack(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? theme.accent : theme.active)
                .frame(width: 36, height: 20)
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .padding(2)
                .shadowStyle(Shadows.sm)
        }
        .animation(.designSpring, value: isOn)
    }
}

// MARK: - Previews

#Preview("Toggle") {
    struct Demo: View {
        @State var a = true
        @State var b = false
        var body: some View {
            VStack(spacing: Spacing.space4) {
                Toggle("Dark Mode", isOn: $a)
                    .toggleStyle(ThemeToggleStyle())
                Toggle("Show Hidden Files", isOn: $b)
                    .toggleStyle(ThemeToggleStyle())
            }
            .padding(24)
            .background(Color(hex: "#121110"))
            .environment(\.theme, Theme(isDark: true, accentColor: .graphite))
        }
    }
    return Demo()
}
