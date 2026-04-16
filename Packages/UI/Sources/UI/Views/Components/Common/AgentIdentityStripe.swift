// AgentIdentityStripe.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A thin colored stripe for agent identity on tab pills and other surfaces.
///
/// The stripe pulses gently for running agents, glows briefly on completion,
/// and shakes on error. Static for all other states.
public struct AgentIdentityStripe: View {
    private let agentColor: AgentColor
    private let status: AgentStatus
    private let width: CGFloat
    private let edge: Edge

    @State private var isPulsing = false
    @State private var glowScale: CGFloat = 1.0
    @State private var shakeOffset: CGFloat = 0

    public init(
        color: AgentColor,
        status: AgentStatus = .idle,
        width: CGFloat = 2,
        edge: Edge = .leading
    ) {
        self.agentColor = color
        self.status = status
        self.width = width
        self.edge = edge
    }

    public var body: some View {
        stripeShape
            .fill(stripeColor)
            .frame(
                width: edge.isVertical ? nil : width,
                height: edge.isVertical ? width : nil
            )
            .opacity(opacityValue)
            .scaleEffect(glowScale)
            .offset(x: shakeOffset)
            .onAppear { startAnimation() }
            .onChange(of: status) { _, _ in startAnimation() }
    }

    // MARK: - Visual

    private var stripeColor: Color {
        switch status {
        case .error: Colors.error
        case .waiting: Colors.warning
        default: agentColor.solid
        }
    }

    private var opacityValue: CGFloat {
        switch status {
        case .running: isPulsing ? 1.0 : 0.6
        case .waiting: isPulsing ? 1.0 : 0.7
        case .complete: 1.0
        case .error: 1.0
        case .idle: 0.6
        }
    }

    private var stripeShape: some Shape {
        RoundedRectangle(cornerRadius: width / 2, style: .continuous)
    }

    // MARK: - Animation

    private func startAnimation() {
        isPulsing = false
        glowScale = 1.0
        shakeOffset = 0

        switch status {
        case .running:
            withAnimation(Animations.heartbeat) { isPulsing = true }

        case .waiting:
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }

        case .complete:
            withAnimation(Animations.glow) { glowScale = 1.5 }
            withAnimation(Animations.glow.delay(0.3)) { glowScale = 1.0 }

        case .error:
            withAnimation(.easeInOut(duration: 0.075).repeatCount(4, autoreverses: true)) {
                shakeOffset = 2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.1)) { shakeOffset = 0 }
            }

        case .idle:
            break
        }
    }
}

// MARK: - Agent Status

public enum AgentStatus: String, Sendable, CaseIterable {
    case running
    case waiting
    case complete
    case error
    case idle
}

// MARK: - Edge Helpers

private extension Edge {
    var isVertical: Bool {
        self == .top || self == .bottom
    }
}

// MARK: - Previews

#Preview("Agent Identity Stripes") {
    HStack(spacing: Spacing.space8) {
        ForEach(Array(AgentColor.palette.prefix(4).enumerated()), id: \.offset) { idx, color in
            VStack(spacing: Spacing.space4) {
                HStack(spacing: 0) {
                    AgentIdentityStripe(
                        color: color,
                        status: AgentStatus.allCases[idx % AgentStatus.allCases.count]
                    )
                    Rectangle()
                        .fill(Color(hex: "#1C1A17"))
                        .frame(width: 80, height: 34)
                }
                .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                Text(color.displayName)
                    .font(Typography.caption)
                    .foregroundStyle(Color(hex: "#9E978C"))
            }
        }
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true, accentColor: .graphite))
}
