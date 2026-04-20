// PlaceholderViews.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct PlaceholderView: View {
    @Environment(\.devysTheme) private var theme

    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: DevysSpacing.space4) {
            // Icon as text representation
            Image(systemName: icon)
                .font(DevysTypography.display.weight(.light))
                .foregroundStyle(theme.textTertiary)
            
            Text(title.lowercased().replacingOccurrences(of: " ", with: "_"))
                .font(DevysTypography.title)
                .foregroundStyle(theme.text)
            
            if !subtitle.isEmpty {
                HStack(spacing: 0) {
                    Text("$ ")
                        .foregroundStyle(theme.textTertiary)
                    Text(subtitle.lowercased())
                        .foregroundStyle(theme.textSecondary)
                }
                .font(DevysTypography.body)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.base)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
