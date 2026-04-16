// FileRow.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A file entry in the sidebar file tree.
///
/// Shows the file name with its extension hidden by default (revealed on hover in text-tertiary).
/// Git status indicator appears at the right edge, and a "..." action button fades in on hover.
/// Selected state shows accentMuted background with accent left border.
public struct FileRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let name: String
    private let depth: Int
    private let gitStatus: GitFileStatus?
    private let isSelected: Bool
    private let isExpanded: Bool?
    private let action: () -> Void

    @State private var isHovered = false

    public init(
        name: String,
        depth: Int = 0,
        gitStatus: GitFileStatus? = nil,
        isSelected: Bool = false,
        isExpanded: Bool? = nil,
        action: @escaping () -> Void
    ) {
        self.name = name
        self.depth = depth
        self.gitStatus = gitStatus
        self.isSelected = isSelected
        self.isExpanded = isExpanded
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.space2) {
                // File icon
                fileIcon
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 16)

                // File name with extension handling
                fileNameView

                Spacer(minLength: Spacing.space1)

                // Git status indicator at right edge
                if let gitStatus {
                    GitStatusIndicator(gitStatus)
                }

                // Hover action button
                Button {
                    // action placeholder
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(Typography.label.weight(.regular))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
            .padding(.leading, indentation + layout.itemPaddingH)
            .padding(.trailing, layout.itemPaddingH)
            .frame(height: layout.sidebarRowHeight)
            .background(backgroundView, in: backgroundShape)
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(theme.accent)
                        .frame(width: 2)
                        .padding(.vertical, Spacing.space1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var fileIcon: some View {
        if let isExpanded {
            Image(systemName: isExpanded ? "folder.fill" : "folder")
        } else {
            Image(systemName: "doc")
        }
    }

    @ViewBuilder
    private var fileNameView: some View {
        let parts = splitFileName(name)
        HStack(spacing: 0) {
            Text(parts.stem)
                .font(Typography.body)
                .foregroundStyle(theme.text)
                .lineLimit(1)

            if let ext = parts.extension {
                Text(".\(ext)")
                    .font(Typography.body)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .opacity(isHovered || isSelected ? 1 : 0)
            }
        }
    }

    // MARK: - Computed Properties

    private var indentation: CGFloat {
        CGFloat(depth) * Spacing.space4
    }

    private var backgroundView: Color {
        if isSelected {
            return theme.accentMuted
        }
        return isHovered ? theme.hover : .clear
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
    }

    // MARK: - Helpers

    private func splitFileName(_ fileName: String) -> (stem: String, extension: String?) {
        guard let dotIndex = fileName.lastIndex(of: "."),
              dotIndex != fileName.startIndex else {
            return (fileName, nil)
        }
        let stem = String(fileName[..<dotIndex])
        let ext = String(fileName[fileName.index(after: dotIndex)...])
        return (stem, ext.isEmpty ? nil : ext)
    }
}

// MARK: - Previews

#Preview("File Rows") {
    VStack(spacing: 0) {
        FileRow(name: "Package.swift", depth: 0, gitStatus: .modified) {}
        FileRow(name: "ContentView.swift", depth: 1, gitStatus: .new, isSelected: true) {}
        FileRow(name: "AppDelegate.swift", depth: 1) {}
        FileRow(name: "README.md", depth: 0, gitStatus: .staged) {}
        FileRow(name: "config.json", depth: 2, gitStatus: .conflict) {}
        FileRow(name: ".gitignore", depth: 0) {}
    }
    .frame(width: 280)
    .padding(.vertical, Spacing.space2)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
