import SwiftUI
import UI
import UIKit

struct IOSAssistantRootView: View {
    @Environment(\.devysTheme) private var theme

    @State private var mode: IOSAssistantMode = .calendar
    @State private var density: IOSAssistantCardDensity = .compact
    @State private var showIntegrationSheet = false
    @State private var integrationStatuses: [IOSAssistantMode: IOSAssistantIntegrationStatus] = .assistantDefaults
    @State private var cardDragYOffset: CGFloat = 0
    @State private var cardDragXOffset: CGFloat = 0
    @State private var cardVisualScale: CGFloat = 1
    @State private var cardVisualOpacity: Double = 1

    @Namespace private var modeStripNamespace
    @Namespace private var cardNamespace

    private let expandedHeightRatio: CGFloat = 0.62

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if density == .expanded {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            collapseCard()
                        }
                }

                VStack(spacing: DevysSpacing.space3) {
                    modeStrip

                    Button {
                        toggleExpanded()
                    } label: {
                        IOSAssistantStatusCardView(
                            mode: mode,
                            density: density,
                            namespace: cardNamespace,
                            maxExpandedHeight: proxy.size.height * expandedHeightRatio,
                            integrationStatus: integrationStatus(for: mode)
                        ) {
                            showIntegrationSheet = true
                        }
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(cardVisualScale)
                    .opacity(cardVisualOpacity)
                    .offset(x: cardDragXOffset, y: cardDragYOffset)
                    .gesture(modeSwitchGesture)
                    .simultaneousGesture(collapseSwipeGesture(cardHeight: proxy.size.height * expandedHeightRatio))
                    .accessibilityLabel("\(mode.title) status")
                    .accessibilityValue(integrationStatus(for: mode).pillText)
                    .accessibilityHint("Double tap to expand details. Swipe down to collapse.")

                    Spacer(minLength: 0)

                    IOSAssistantComposerView(mode: mode) { _ in
                        withAnimation(DevysAnimation.default) {
                            density = .medium
                        }
                    }
                }
                .padding(.horizontal, DevysSpacing.space4)
                .padding(.top, DevysSpacing.space2)
                .padding(.bottom, DevysSpacing.space4)
            }
            .background(theme.base)
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radius))
        }
        .sheet(isPresented: $showIntegrationSheet) {
            IOSAssistantIntegrationSheet(statuses: $integrationStatuses)
                .environment(\.devysTheme, theme)
        }
    }

    private var modeStrip: some View {
        HStack(spacing: DevysSpacing.space2) {
            ForEach(IOSAssistantMode.allCases) { item in
                Button {
                    selectMode(item)
                } label: {
                    HStack(spacing: DevysSpacing.space1) {
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
                                .matchedGeometryEffect(id: "ios-mode-strip-indicator", in: modeStripNamespace)
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
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                        showIntegrationSheet = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                )
                .accessibilityLabel("\(item.title) mode")
                .accessibilityHint("Switch to \(item.title). Long press to manage this integration.")
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
            .accessibilityLabel("Manage integrations")
            .accessibilityHint("Open integration settings")
        }
    }

    private var modeSwitchGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                cardDragXOffset = value.translation.width * 0.35
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 56 else {
                    withAnimation(DevysAnimation.spring) {
                        cardDragXOffset = 0
                    }
                    return
                }

                let step = value.translation.width < 0 ? 1 : -1
                if value.translation.width < 0 {
                    withAnimation(DevysAnimation.fast) {
                        cardDragXOffset = -28
                    }
                } else {
                    withAnimation(DevysAnimation.fast) {
                        cardDragXOffset = 28
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    selectRelativeMode(step: step)
                    cardDragXOffset = -CGFloat(step) * 28
                    withAnimation(DevysAnimation.spring) {
                        cardDragXOffset = 0
                    }
                }
            }
    }

    private func collapseSwipeGesture(cardHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard density == .expanded else { return }
                let translation = max(0, value.translation.height)
                let threshold = cardHeight * 0.5
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.82)) {
                    cardDragYOffset = rubberBandOffset(translation, threshold: threshold)
                }
            }
            .onEnded { value in
                guard density == .expanded else {
                    cardDragYOffset = 0
                    return
                }

                let translation = max(0, value.translation.height)
                let threshold = cardHeight * 0.5
                if translation > threshold {
                    collapseCard()
                }

                withAnimation(DevysAnimation.spring) {
                    cardDragYOffset = 0
                }
            }
    }

    private func integrationStatus(for mode: IOSAssistantMode) -> IOSAssistantIntegrationStatus {
        integrationStatuses[mode] ?? .disconnected
    }

    private func selectMode(_ newMode: IOSAssistantMode) {
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

    private func selectRelativeMode(step: Int) {
        guard let index = IOSAssistantMode.allCases.firstIndex(of: mode) else { return }
        let count = IOSAssistantMode.allCases.count
        let next = (index + step + count) % count
        selectMode(IOSAssistantMode.allCases[next])
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

    private func rubberBandOffset(_ translation: CGFloat, threshold: CGFloat) -> CGFloat {
        guard translation > 0 else { return 0 }
        guard translation > threshold else { return translation }

        let overshoot = translation - threshold
        return threshold + (overshoot * 0.25)
    }
}

#Preview {
    IOSAssistantRootView()
        .environment(\.devysTheme, DevysTheme(isDark: true, accentColor: .white))
}
