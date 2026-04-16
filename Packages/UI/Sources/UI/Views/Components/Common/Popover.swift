// Popover.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

// MARK: - Devys Popover

/// A themed popover container with signature spring animation and dismiss-on-click-outside.
///
/// Use for FAB menus, branch pickers, tab overflow dropdowns, and other floating panels.
///
/// ```swift
/// DevysPopover(isPresented: $showMenu) {
///     VStack { /* menu content */ }
/// }
/// ```
public struct DevysPopover<Content: View>: View {
    @Environment(\.theme) private var theme

    @Binding private var isPresented: Bool
    private let anchor: UnitPoint
    private let content: () -> Content

    @State private var animateIn = false

    public init(
        isPresented: Binding<Bool>,
        anchor: UnitPoint = .top,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.anchor = anchor
        self.content = content
    }

    public var body: some View {
        if isPresented {
            ZStack {
                // Dismiss backdrop — transparent tap catcher
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismissPopover() }

                // Popover content
                content()
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    )
                    .background(
                        theme.overlay,
                        in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    )
                    .elevation(.popover)
                    .scaleEffect(animateIn ? 1.0 : 0.95, anchor: anchor)
                    .opacity(animateIn ? 1.0 : 0)
            }
            .onAppear {
                withAnimation(Animations.spring) { animateIn = true }
            }
            .onDisappear { animateIn = false }
        }
    }

    private func dismissPopover() {
        withAnimation(.easeOut(duration: 0.12)) { animateIn = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isPresented = false
        }
    }
}

// MARK: - Previews

#Preview("Popover") {
    struct Demo: View {
        @State var showPopover = true

        var body: some View {
            ZStack {
                Color(hex: "#121110")
                    .ignoresSafeArea()

                VStack(spacing: Spacing.space4) {
                    ActionButton("Toggle Popover", style: .primary) {
                        showPopover.toggle()
                    }

                    DevysPopover(isPresented: $showPopover, anchor: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(
                                ["New Terminal", "New Agent", "Open File"],
                                id: \.self
                            ) { item in
                                Text(item)
                                    .font(Typography.body)
                                    .foregroundStyle(Theme(isDark: true).text)
                                    .padding(.horizontal, Spacing.space3)
                                    .padding(.vertical, Spacing.space2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(width: 200)
                        .padding(.vertical, Spacing.space1)
                    }
                }
            }
            .frame(width: 400, height: 300)
            .environment(\.theme, Theme(isDark: true))
        }
    }
    return Demo()
}
