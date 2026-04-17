import AppFeatures
import SwiftUI
import UI

@MainActor
struct WorkflowFormField<Content: View>: View {
    @Environment(\.devysTheme) private var theme

    let title: String
    private let content: Content

    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)
            content
        }
    }
}

@MainActor
struct WorkflowPromptEditor: View {
    @Environment(\.devysTheme) private var theme

    let title: String
    let text: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)

            TextEditorField(text: text, minHeight: 150, isMonospaced: true)
        }
    }
}

@MainActor
struct WorkflowRunStatusChip: View {
    @Environment(\.devysTheme) private var theme

    let status: WorkflowRunStatus

    var body: some View {
        WorkflowMetaChip(
            title: title,
            icon: icon,
            tint: tint
        )
    }

    private var title: String {
        switch status {
        case .idle:
            "Idle"
        case .running:
            "Running"
        case .awaitingOperator:
            "Awaiting Choice"
        case .interrupted:
            "Interrupted"
        case .failed:
            "Failed"
        case .completed:
            "Completed"
        }
    }

    private var icon: String {
        switch status {
        case .idle:
            "pause.circle"
        case .running:
            "play.circle.fill"
        case .awaitingOperator:
            "arrow.triangle.branch"
        case .interrupted:
            "stop.circle"
        case .failed:
            "exclamationmark.circle"
        case .completed:
            "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .idle:
            theme.textSecondary
        case .running:
            theme.accent
        case .awaitingOperator, .interrupted:
            theme.warning
        case .failed:
            theme.error
        case .completed:
            theme.success
        }
    }
}

@MainActor
struct WorkflowMetaChip: View {
    @Environment(\.devysTheme) private var theme

    let title: String
    let icon: String
    var tint: Color?

    var body: some View {
        HStack(spacing: Spacing.space1) {
            Image(systemName: icon)
            Text(title)
        }
        .font(Typography.micro)
        .foregroundStyle(tint ?? theme.textSecondary)
        .padding(.horizontal, Spacing.space2)
        .padding(.vertical, Spacing.space1)
        .background(theme.hover, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
    }
}

@MainActor
func workflowBinding<Value: Sendable>(
    value: Value,
    _ onChange: @escaping (Value) -> Void
) -> Binding<Value> {
    Binding(
        get: { value },
        set: { updatedValue in
            onChange(updatedValue)
        }
    )
}
