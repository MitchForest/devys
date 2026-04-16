// GitStatusIndicator.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Visual git file status indicator replacing traditional U/M/A/D letters.
///
/// Uses small colored symbols for instant pattern recognition:
/// `+` new, `●` modified, `◕` staged, `−` deleted, `→` renamed, `!` conflict
public struct GitStatusIndicator: View {
    @Environment(\.theme) private var theme

    private let status: GitFileStatus

    public init(_ status: GitFileStatus) {
        self.status = status
    }

    public var body: some View {
        Group {
            switch status {
            case .new:
                Text("+")
                    .font(Typography.Code.sm.weight(.bold))
                    .foregroundStyle(theme.success)

            case .modified:
                Circle()
                    .fill(theme.warning)
                    .frame(width: 6, height: 6)

            case .staged:
                stagedDot

            case .deleted:
                Text("−")
                    .font(Typography.Code.sm.weight(.bold))
                    .foregroundStyle(theme.error)

            case .renamed:
                Text("→")
                    .font(Typography.Code.gutter.weight(.medium))
                    .foregroundStyle(theme.info)

            case .conflict:
                Text("!")
                    .font(Typography.Code.gutter.weight(.bold))
                    .foregroundStyle(theme.error)

            case .ignored:
                EmptyView()
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel(status.accessibilityLabel)
        .help(status.tooltip)
    }

    private var stagedDot: some View {
        ZStack {
            Circle()
                .stroke(theme.success, lineWidth: 1.5)
                .frame(width: 6, height: 6)
            Circle()
                .fill(theme.success)
                .frame(width: 6, height: 6)
                .clipShape(HalfCircle())
        }
    }
}

// MARK: - Half Circle Clip

private struct HalfCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: 0, y: 0, width: rect.width / 2, height: rect.height))
        return path
    }
}

// MARK: - Git File Status

public enum GitFileStatus: String, Sendable, CaseIterable {
    case new
    case modified
    case staged
    case deleted
    case renamed
    case conflict
    case ignored

    public var accessibilityLabel: String {
        switch self {
        case .new: "New file"
        case .modified: "Modified"
        case .staged: "Staged"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .conflict: "Conflict"
        case .ignored: "Ignored"
        }
    }

    public var tooltip: String {
        switch self {
        case .new: "New file — not yet tracked by git"
        case .modified: "Modified — has unstaged changes"
        case .staged: "Staged — ready to commit"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .conflict: "Conflict — needs manual resolution"
        case .ignored: "Ignored by .gitignore"
        }
    }
}

// MARK: - Previews

#Preview("Git Status Indicators") {
    VStack(alignment: .leading, spacing: Spacing.space3) {
        ForEach(GitFileStatus.allCases, id: \.self) { status in
            HStack(spacing: Spacing.space3) {
                GitStatusIndicator(status)
                Text(status.rawValue)
                    .font(Typography.body)
                    .foregroundStyle(Color(hex: "#EDE8E0"))
            }
        }
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true, accentColor: .graphite))
}
