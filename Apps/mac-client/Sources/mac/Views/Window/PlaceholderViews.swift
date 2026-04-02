// PlaceholderViews.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import GhosttyTerminal
import UI

struct PlaceholderSidebarView: View {
    @Environment(\.devysTheme) private var theme

    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Header - terminal style
                HStack {
                    Text(title.uppercased().replacingOccurrences(of: " ", with: "_"))
                        .font(DevysTypography.heading)
                        .tracking(DevysTypography.headerTracking)
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, DevysSpacing.space3)
                .padding(.vertical, DevysSpacing.space2)

                // Content
                VStack(spacing: DevysSpacing.space3) {
                    Spacer()
                    
                    Text("[ \(icon) ]")
                        .font(DevysTypography.xl)
                        .foregroundStyle(theme.textTertiary)
                    
                    Text(title.lowercased())
                        .font(DevysTypography.md)
                        .foregroundStyle(theme.text)
                    
                    Text("$ coming_soon...")
                        .font(DevysTypography.sm)
                        .foregroundStyle(theme.textSecondary)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Right border
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(width: 1)
        }
        .background(theme.surface)
    }
}

struct PlaceholderView: View {
    @Environment(\.devysTheme) private var theme

    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: DevysSpacing.space4) {
            // Icon as text representation
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.textTertiary)
            
            Text(title.lowercased().replacingOccurrences(of: " ", with: "_"))
                .font(DevysTypography.lg)
                .foregroundStyle(theme.text)
            
            if !subtitle.isEmpty {
                HStack(spacing: 0) {
                    Text("$ ")
                        .foregroundStyle(theme.textTertiary)
                    Text(subtitle.lowercased())
                        .foregroundStyle(theme.textSecondary)
                }
                .font(DevysTypography.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.base)
    }
}

struct TerminalRewritePlaceholderView: View {
    @Environment(\.devysTheme) private var theme

    let workingDirectory: URL?
    let requestedCommand: String?

    private let ghosttyStatus = GhosttyBootstrap.status

    private var directoryLabel: String? {
        workingDirectory?.lastPathComponent.nilIfEmpty
    }

    private var commandLabel: String? {
        requestedCommand?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space4) {
            VStack(alignment: .leading, spacing: DevysSpacing.space2) {
                Text("terminal_unavailable")
                    .font(DevysTypography.lg)
                    .foregroundStyle(theme.text)

                Text("$ rebuilding_on_libghostty")
                    .font(DevysTypography.sm)
                    .foregroundStyle(theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: DevysSpacing.space2) {
                if let directoryLabel {
                    placeholderLine(label: "cwd", value: directoryLabel)
                }

                if let commandLabel {
                    placeholderLine(label: "command", value: commandLabel)
                }

                placeholderLine(label: "status", value: "stubbed_phase_1")
                placeholderLine(label: "ghostty", value: ghosttyStatus.frameworkStateLabel)
                placeholderLine(label: "source", value: ghosttyStatus.sourceStateLabel)
                placeholderLine(label: "commit", value: ghosttyStatus.shortCommit)
                placeholderLine(label: "zig_min", value: ghosttyStatus.minimumZigVersion)
                placeholderLine(label: "next", value: "build_ghostty_surface")
            }

            Text(
                "The legacy terminal is intentionally disabled on this branch "
                    + "while the new Ghostty-backed terminal is built from scratch."
            )
                .font(DevysTypography.sm)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(DevysSpacing.space6)
        .background(theme.base)
    }

    @ViewBuilder
    private func placeholderLine(label: String, value: String) -> some View {
        HStack(spacing: DevysSpacing.space2) {
            Text("\(label):")
                .foregroundStyle(theme.textTertiary)
            Text(value.lowercased().replacingOccurrences(of: " ", with: "_"))
                .foregroundStyle(theme.textSecondary)
        }
        .font(DevysTypography.sm)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
