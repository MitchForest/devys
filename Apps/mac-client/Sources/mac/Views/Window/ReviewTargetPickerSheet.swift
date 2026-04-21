import AppFeatures
import SwiftUI
import UI

struct ReviewTargetPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let presentation: WindowFeature.ReviewEntryPresentation
    let onSelect: (ReviewTargetKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space4) {
            Text("Review…")
                .font(Typography.title)
                .foregroundStyle(theme.text)

            Text(headerSubtitle)
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)

            VStack(spacing: Spacing.space3) {
                ForEach(presentation.availableTargets, id: \.self) { targetKind in
                    targetButton(targetKind)
                }
            }

            HStack {
                Spacer()
                ActionButton("Cancel", style: .ghost) {
                    onCancel()
                    dismiss()
                }
            }
        }
        .padding(Spacing.space5)
        .frame(width: 520)
        .elevation(.overlay)
    }

    private var headerSubtitle: String {
        if presentation.branchName.isEmpty {
            return "Choose what to audit in \(presentation.workspaceName)."
        }

        return "Choose what to audit in \(presentation.workspaceName) on \(presentation.branchName)."
    }

    private func targetButton(
        _ targetKind: ReviewTargetKind
    ) -> some View {
        Button {
            onSelect(targetKind)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: Spacing.space3) {
                DevysIcon(iconName(for: targetKind), size: 18)
                    .foregroundStyle(theme.accent)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(targetLabel(for: targetKind))
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(theme.text)

                    Text(targetKind.pickerSubtitle)
                        .font(Typography.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.space4)
            .elevation(.card)
        }
        .buttonStyle(.plain)
    }

    private func targetLabel(
        for targetKind: ReviewTargetKind
    ) -> String {
        switch targetKind {
        case .pullRequest:
            if let pullRequestNumber = presentation.pullRequestNumber {
                return "Pull Request (#\(pullRequestNumber))"
            }
            return targetKind.displayTitle
        case .currentBranch where !presentation.branchName.isEmpty:
            return "\(targetKind.displayTitle) (\(presentation.branchName))"
        default:
            return targetKind.displayTitle
        }
    }

    private func iconName(
        for targetKind: ReviewTargetKind
    ) -> String {
        switch targetKind {
        case .unstagedChanges:
            "pencil.line"
        case .stagedChanges:
            "square.stack.3d.up.fill"
        case .lastCommit:
            "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .currentBranch:
            "arrow.triangle.branch"
        case .commitRange:
            "line.3.horizontal.decrease.circle"
        case .pullRequest:
            "point.3.connected.trianglepath.dotted"
        case .selection:
            "selection.pin.in.out"
        }
    }
}
