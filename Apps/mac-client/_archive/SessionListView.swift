// SessionListView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import ChatUI
import UI

struct SessionListView: View {
    @Environment(\.devysTheme) private var theme

    let store: SessionListStore
    let onSelectSession: (Session) -> Void
    let onOpenSession: (Session) -> Void
    let onNewSession: () -> Void
    let onArchiveSession: (Session) -> Void
    let onDeleteSession: (Session) -> Void

    var body: some View {
        HStack(spacing: 0) {
            List(selection: selectedSessionBinding) {
                ForEach(store.sessions) { session in
                    SessionRow(session: session, isSelected: session.id == store.selectedSessionID)
                        .tag(Optional(session.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectSession(session)
                        }
                        .onTapGesture(count: 2) {
                            onOpenSession(session)
                        }
                        .contextMenu {
                            Button("Archive") {
                                onArchiveSession(session)
                            }
                            Button("Delete", role: .destructive) {
                                onDeleteSession(session)
                            }
                        }
                }
            }
            .listStyle(.sidebar)

            VStack {
                Button {
                    onNewSession()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("new_session")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Divider()

                Spacer()
            }
            .frame(width: 160)
            .background(theme.surface)
        }
    }

    private var selectedSessionBinding: Binding<String?> {
        Binding(
            get: { store.selectedSessionID },
            set: { newValue in
                Task { await onSelectSessionByID(newValue) }
            }
        )
    }

    private func onSelectSessionByID(_ sessionID: String?) async {
        guard let sessionID else {
            return
        }
        if let session = store.sessions.first(where: { $0.id == sessionID }) {
            onSelectSession(session)
        }
    }
}

private struct SessionRow: View {
    @Environment(\.devysTheme) private var theme
    let session: Session
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: session.harnessType.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)

                Text(session.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Spacer()
            }

            HStack(spacing: 6) {
                Text(session.lastMessagePreview ?? "\(session.harnessType.rawValue) · \(session.model)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)

                Spacer()

                if hasUnread {
                    unreadBadge
                } else if let statusIcon {
                    Image(systemName: statusIcon)
                        .font(.system(size: statusIcon == "circlebadge.fill" ? 8 : 11))
                        .foregroundStyle(statusColor)
                }

                Text(relativeDate)
                    .font(.system(size: 10))
                    .foregroundStyle(hasUnread ? theme.accent : theme.textTertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? theme.elevated.opacity(0.65) : Color.clear)
        )
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.updatedAt, relativeTo: Date())
    }

    private var hasUnread: Bool {
        session.unreadCount > 0
    }

    @ViewBuilder
    private var unreadBadge: some View {
        Text("\(session.unreadCount)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.base)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.accent)
            .clipShape(Capsule())
    }

    private var statusIcon: String? {
        switch session.status {
        case .streaming:
            return "circlebadge.fill"
        case .waitingInput:
            return "exclamationmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        default:
            return nil
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .streaming:
            return .green
        case .waitingInput:
            return .orange
        case .failed:
            return .red
        default:
            return theme.textTertiary
        }
    }
}
