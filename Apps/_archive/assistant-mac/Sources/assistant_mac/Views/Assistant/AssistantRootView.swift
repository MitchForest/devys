// AssistantRootView.swift
// Phase 1 assistant shell.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct AssistantRootView: View {
    @Environment(\.devysTheme) private var theme

    @State private var mode: AssistantMode = .calendar
    @State private var density: AssistantCardDensity = .compact
    @State private var showIntegrationSheet = false
    @State private var integrationStatuses: [AssistantMode: AssistantIntegrationStatus] = .assistantDefaults
    @State private var cardVisualScale: CGFloat = 1
    @State private var cardVisualOpacity: Double = 1

    @Namespace private var modeStripNamespace
    @Namespace private var cardNamespace

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                theme.base
                    .ignoresSafeArea()

                if density == .expanded {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            collapseCard()
                        }
                }

                VStack(spacing: DevysSpacing.space4) {
                    modeStrip

                    statusCard(proxy: proxy)

                    Spacer(minLength: 0)

                    AssistantComposerView(mode: mode) { _ in
                        withAnimation(DevysAnimation.default) {
                            density = .medium
                        }
                    }
                    .frame(maxWidth: min(720, proxy.size.width - (DevysSpacing.space6 * 2)))
                }
                .padding(DevysSpacing.space6)
            }
        }
        .onExitCommand {
            guard density == .expanded else { return }
            collapseCard()
        }
        .sheet(isPresented: $showIntegrationSheet) {
            AssistantIntegrationSheet(integrationStatuses: $integrationStatuses)
                .environment(\.devysTheme, theme)
        }
    }

    private var modeStrip: some View {
        HStack(spacing: DevysSpacing.space2) {
            ForEach(AssistantMode.allCases) { item in
                Button {
                    selectMode(item)
                } label: {
                    HStack(spacing: DevysSpacing.space2) {
                        Image(systemName: item.icon)
                            .font(.system(size: DevysSpacing.iconMd))
                        Text(item.shortTitle)
                            .font(DevysTypography.caption)
                    }
                    .foregroundStyle(mode == item ? item.accent : theme.textTertiary)
                    .padding(.horizontal, DevysSpacing.space3)
                    .padding(.vertical, DevysSpacing.space2)
                    .background {
                        if mode == item {
                            RoundedRectangle(cornerRadius: DevysSpacing.radiusXl)
                                .fill(item.accent.opacity(0.12))
                                .matchedGeometryEffect(id: "mode-strip-indicator", in: modeStripNamespace)
                        } else {
                            RoundedRectangle(cornerRadius: DevysSpacing.radiusXl)
                                .fill(Color.clear)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: DevysSpacing.radiusXl)
                            .strokeBorder(mode == item ? item.accent.opacity(0.25) : theme.borderSubtle, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title) mode")
                .accessibilityHint("Switch assistant mode")
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }

            Spacer(minLength: 0)

            Button {
                showIntegrationSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: DevysSpacing.iconMd))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
                    .overlay {
                        RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                            .strokeBorder(theme.borderSubtle, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help("Manage integrations")
            .accessibilityLabel("Manage integrations")
            .accessibilityHint("Open integration settings")
        }
    }

    private func statusCard(proxy: GeometryProxy) -> some View {
        Button {
            toggleExpanded()
        } label: {
            AssistantStatusCardView(
                mode: mode,
                density: density,
                namespace: cardNamespace,
                maxExpandedHeight: proxy.size.height * 0.68,
                integrationStatus: integrationStatus(for: mode)
            ) {
                showIntegrationSheet = true
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(cardVisualScale)
        .opacity(cardVisualOpacity)
        .frame(maxWidth: min(720, proxy.size.width - (DevysSpacing.space6 * 2)))
        .onHover { hovering in
            handleHover(hovering)
        }
        .accessibilityLabel(statusCardAccessibilityLabel)
        .accessibilityHint("Press Space or Return to expand. Press Escape to collapse.")
    }

    private var statusCardAccessibilityLabel: String {
        "\(mode.title) status \(integrationStatus(for: mode).pillText)"
    }

    private func integrationStatus(for mode: AssistantMode) -> AssistantIntegrationStatus {
        integrationStatuses[mode] ?? .disconnected
    }

    private func selectMode(_ newMode: AssistantMode) {
        guard mode != newMode else { return }

        withAnimation(DevysAnimation.fast) {
            density = .compact
            cardVisualScale = 0.97
            cardVisualOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            mode = newMode
            cardVisualScale = 0.97
            cardVisualOpacity = 0

            withAnimation(DevysAnimation.default) {
                cardVisualScale = 1
                cardVisualOpacity = 1
            }
        }
    }

    private func handleHover(_ hovering: Bool) {
        guard density != .expanded else { return }
        withAnimation(hovering ? DevysAnimation.default : DevysAnimation.fast) {
            density = hovering ? .medium : .compact
        }
    }

    private func toggleExpanded() {
        switch density {
        case .expanded:
            collapseCard()
        case .compact, .medium:
            withAnimation(DevysAnimation.smoothSpring) {
                density = .expanded
            }
        }
    }

    private func collapseCard() {
        withAnimation(DevysAnimation.spring) {
            density = .compact
        }
    }
}

#Preview {
    AssistantRootView()
        .environment(\.devysTheme, DevysTheme(isDark: true, accentColor: .white))
        .frame(width: 960, height: 680)
}
