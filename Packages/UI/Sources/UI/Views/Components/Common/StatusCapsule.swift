// StatusCapsule.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

// MARK: - Status Icon

/// Icon representing the current repo cleanliness state.
public enum StatusIcon: Sendable {
    case clean
    case warning
    case error

    var systemName: String {
        switch self {
        case .clean: "checkmark"
        case .warning: "exclamationmark"
        case .error: "xmark"
        }
    }

    func color(theme: Theme) -> Color {
        switch self {
        case .clean: theme.success
        case .warning: theme.warning
        case .error: theme.error
        }
    }
}

// MARK: - Status Capsule

/// Floating status pill showing branch, sync state, repo status, and active agents.
///
/// Sits at the bottom center of the window (positioned by the consumer).
/// Auto-hides after 3 seconds of inactivity, reappears on hover.
/// Expands on hover to reveal git action buttons and agent details.
public struct StatusCapsule: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let branchName: String?
    private let aheadCount: Int
    private let behindCount: Int
    private let agentCount: Int
    private let agentColors: [AgentColor]
    private let statusIcon: StatusIcon
    private let onTap: (() -> Void)?

    @Binding private var isExpanded: Bool
    @State private var isHovered = false
    @State private var autoHidden = false
    @State private var hideTimer: Task<Void, Never>?

    public init(
        branchName: String? = nil,
        aheadCount: Int = 0,
        behindCount: Int = 0,
        agentCount: Int = 0,
        agentColors: [AgentColor] = [],
        statusIcon: StatusIcon = .clean,
        isExpanded: Binding<Bool>,
        onTap: (() -> Void)? = nil
    ) {
        self.branchName = branchName
        self.aheadCount = aheadCount
        self.behindCount = behindCount
        self.agentCount = agentCount
        self.agentColors = agentColors
        self.statusIcon = statusIcon
        self._isExpanded = isExpanded
        self.onTap = onTap
    }

    public var body: some View {
        VStack(spacing: Spacing.space1) {
            collapsedRow

            if isExpanded {
                expandedRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, layout.capsulePaddingV)
        .padding(.horizontal, layout.capsulePaddingH)
        .frame(minWidth: Spacing.capsuleMinWidth)
        .background(theme.overlay, in: Capsule())
        .shadowStyle(isExpanded ? Shadows.md : Shadows.sm)
        .opacity(capsuleOpacity)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
            if hovering {
                withAnimation(Animations.spring) { isExpanded = true }
                // Cancel auto-hide and show
                autoHidden = false
                resetHideTimer()
            } else {
                withAnimation(Animations.spring) { isExpanded = false }
                resetHideTimer()
            }
        }
        .onTapGesture { onTap?() }
        .onAppear { resetHideTimer() }
        .onDisappear { hideTimer?.cancel() }
        .animation(Animations.spring, value: isExpanded)
    }

    // MARK: - Collapsed Row

    private var collapsedRow: some View {
        HStack(spacing: Spacing.space2) {
            // Branch icon + name
            Image(systemName: "arrow.triangle.branch")
                .font(Typography.micro)
                .foregroundStyle(theme.textSecondary)

            if let branchName {
                Text(branchName)
                    .font(Typography.label)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }

            // Ahead / behind counts
            if aheadCount > 0 {
                Text("\u{2191}\(aheadCount)")
                    .font(Typography.micro)
                    .foregroundStyle(theme.info)
            }

            if behindCount > 0 {
                Text("\u{2193}\(behindCount)")
                    .font(Typography.micro)
                    .foregroundStyle(theme.warning)
            }

            // Status icon
            Image(systemName: statusIcon.systemName)
                .font(Typography.micro.weight(.semibold))
                .foregroundStyle(statusIcon.color(theme: theme))

            // Agent dots
            if !agentColors.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(agentColors.enumerated()), id: \.offset) { _, agentColor in
                        Circle()
                            .fill(agentColor.solid)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
    }

    // MARK: - Expanded Row

    private var expandedRow: some View {
        HStack(spacing: Spacing.space2) {
            ActionButton("Fetch", icon: "arrow.down.circle", style: .ghost) {}
            ActionButton("Pull", icon: "arrow.down.to.line", style: .ghost) {}
            ActionButton("Push", icon: "arrow.up.to.line", style: .ghost) {}

            if agentCount > 0 {
                Spacer()
                Text("\(agentCount) agent\(agentCount == 1 ? "" : "s")")
                    .font(Typography.micro)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    // MARK: - Opacity

    private var capsuleOpacity: Double {
        if autoHidden && !isHovered {
            return 0
        }
        return isHovered || isExpanded ? 1.0 : 0.8
    }

    // MARK: - Auto-Hide Timer

    private func resetHideTimer() {
        hideTimer?.cancel()
        hideTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(Animations.glow) { autoHidden = true }
        }
    }
}

// MARK: - Previews

#Preview("Status Capsule — Clean") {
    struct Demo: View {
        @State var isExpanded = false

        var body: some View {
            ZStack {
                Color(hex: "#121110")
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    StatusCapsule(
                        branchName: "main",
                        aheadCount: 0,
                        behindCount: 0,
                        agentCount: 0,
                        agentColors: [],
                        statusIcon: .clean,
                        isExpanded: $isExpanded
                    )
                    .padding(.bottom, Spacing.space4)
                }
            }
            .frame(width: 500, height: 300)
            .environment(\.theme, Theme(isDark: true))
        }
    }
    return Demo()
}

#Preview("Status Capsule — Active") {
    struct Demo: View {
        @State var isExpanded = true

        var body: some View {
            ZStack {
                Color(hex: "#121110")
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    StatusCapsule(
                        branchName: "feat/tca-refactor",
                        aheadCount: 3,
                        behindCount: 1,
                        agentCount: 2,
                        agentColors: [AgentColor.forIndex(0), AgentColor.forIndex(1)],
                        statusIcon: .warning,
                        isExpanded: $isExpanded
                    )
                    .padding(.bottom, Spacing.space4)
                }
            }
            .frame(width: 500, height: 300)
            .environment(\.theme, Theme(isDark: true))
        }
    }
    return Demo()
}

#Preview("Status Capsule — Error") {
    struct Demo: View {
        @State var isExpanded = false

        var body: some View {
            ZStack {
                Color(hex: "#121110")
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    StatusCapsule(
                        branchName: "hotfix/crash",
                        aheadCount: 1,
                        behindCount: 0,
                        agentCount: 3,
                        agentColors: [
                            AgentColor.forIndex(2),
                            AgentColor.forIndex(3),
                            AgentColor.forIndex(5),
                        ],
                        statusIcon: .error,
                        isExpanded: $isExpanded
                    )
                    .padding(.bottom, Spacing.space4)
                }
            }
            .frame(width: 500, height: 300)
            .environment(\.theme, Theme(isDark: true))
        }
    }
    return Demo()
}
