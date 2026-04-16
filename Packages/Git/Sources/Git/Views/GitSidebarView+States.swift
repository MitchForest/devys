// GitSidebarView+States.swift
// Empty states and footer actions for GitSidebarView.

import SwiftUI
import UI

extension GitSidebarView {
    var nonRepositoryStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 24))
                .foregroundStyle(theme.textTertiary.opacity(0.8))

            Text("Git not initialized")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            Text("Open the project now and initialize Git later when you need source control.")
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading...")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(DevysColors.success.opacity(0.6))

            Text("No Changes")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            Text("Working tree is clean")
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var actionsFooter: some View {
        if !store.isRepositoryAvailable {
            return AnyView(nonRepositoryActionsFooter)
        }
        return AnyView(repositoryActionsFooter)
    }

    private var nonRepositoryActionsFooter: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.initializeRepository() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Initialize Git")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.overlay)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var repositoryActionsFooter: some View {
        HStack(spacing: 8) {
            Button {
                showingCommitSheet = true
            } label: {
                HStack(spacing: 4) {
                    Text(">")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.accent)
                    Text("commit")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.overlay)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        .strokeBorder(
                            store.stagedChanges.isEmpty ? theme.border : theme.accent,
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.stagedChanges.isEmpty)
            .opacity(store.stagedChanges.isEmpty ? 0.5 : 1.0)

            Spacer()

            Button {
                Task { await store.fetch() }
            } label: {
                Image(systemName: "arrow.trianglehead.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Fetch")
            .disabled(store.isLoading)

            Button {
                Task { await store.pull() }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Pull")
            .disabled(store.isLoading)

            Button {
                Task { await store.push() }
            } label: {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Push")
            .disabled(store.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
