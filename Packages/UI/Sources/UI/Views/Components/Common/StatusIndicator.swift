// StatusIndicator.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A colored status indicator dot.
///
/// Use sparingly - only for actionable status information.
struct StatusIndicator: View {
    // MARK: - Properties
    
    private let status: Status
    private let size: CGFloat
    private let isAnimated: Bool
    
    @State private var pulseAnimation = false
    
    // MARK: - Initialization
    
    init(
        _ status: Status,
        size: CGFloat = 8,
        isAnimated: Bool = false
    ) {
        self.status = status
        self.size = size
        self.isAnimated = isAnimated
    }
    
    // MARK: - Body
    
    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .overlay {
                if status == .running && isAnimated {
                    Circle()
                        .stroke(status.color.opacity(0.4), lineWidth: 1.5)
                        .frame(width: size + 4, height: size + 4)
                        .scaleEffect(pulseAnimation ? 1.8 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                            value: pulseAnimation
                        )
                }
            }
            .onAppear {
                if status == .running && isAnimated {
                    pulseAnimation = true
                }
            }
    }
}

// MARK: - Status

extension StatusIndicator {
    enum Status: Sendable {
        case running
        case pending
        case complete
        case error
        case inactive
    }
}

extension StatusIndicator.Status {
    var color: Color {
        switch self {
        case .running: return DevysColors.success
        case .pending: return DevysColors.warning
        case .complete: return DevysColors.success.opacity(0.7)  // Subtle success variant
        case .error: return DevysColors.error
        case .inactive: return DevysColors.darkTextTertiary
        }
    }
}

// MARK: - Previews

#Preview("Status Indicators") {
    HStack(spacing: DevysSpacing.space6) {
        VStack(spacing: DevysSpacing.space2) {
            StatusIndicator(.running, isAnimated: true)
            Text("Running")
                .font(DevysTypography.caption)
        }
        
        VStack(spacing: DevysSpacing.space2) {
            StatusIndicator(.pending)
            Text("Pending")
                .font(DevysTypography.caption)
        }
        
        VStack(spacing: DevysSpacing.space2) {
            StatusIndicator(.complete)
            Text("Complete")
                .font(DevysTypography.caption)
        }
        
        VStack(spacing: DevysSpacing.space2) {
            StatusIndicator(.error)
            Text("Error")
                .font(DevysTypography.caption)
        }
        
        VStack(spacing: DevysSpacing.space2) {
            StatusIndicator(.inactive)
            Text("Inactive")
                .font(DevysTypography.caption)
        }
    }
    .padding()
    .background(DevysColors.bg0)
    .foregroundStyle(DevysColors.textSecondary)
}
