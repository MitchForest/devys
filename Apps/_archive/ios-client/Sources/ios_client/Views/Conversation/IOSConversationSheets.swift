import ChatUI
import SwiftUI
import UI

// MARK: - Approval Sheet

struct IOSApprovalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let request: AppStore.PendingApprovalRequest
    @Binding var note: String
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                header
                promptCard
                noteField
                actionButtons
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.base)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 28))
                .foregroundStyle(DevysColors.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("Approval Required")
                    .font(ChatTokens.title)
                    .foregroundStyle(theme.text)

                Text("The agent needs your permission to proceed.")
                    .font(ChatTokens.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var promptCard: some View {
        Text(request.prompt)
            .font(ChatTokens.body)
            .foregroundStyle(theme.text)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var noteField: some View {
        TextField("Optional note...", text: $note, axis: .vertical)
            .font(ChatTokens.secondary)
            .lineLimit(1 ... 3)
            .padding(12)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                onDeny()
                dismiss()
            } label: {
                Text("Deny")
                    .font(ChatTokens.bodyBold)
                    .foregroundStyle(DevysColors.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DevysColors.error.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                onApprove()
                dismiss()
            } label: {
                Text("Approve")
                    .font(ChatTokens.bodyBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DevysColors.success)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Input Sheet

struct IOSInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let request: AppStore.PendingInputRequest
    @Binding var value: String
    let onSubmit: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                header
                promptCard
                inputField
                submitButton
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.base)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 28))
                .foregroundStyle(ChatTokens.userBubble)

            VStack(alignment: .leading, spacing: 2) {
                Text("Input Requested")
                    .font(ChatTokens.title)
                    .foregroundStyle(theme.text)

                Text("The agent needs information from you.")
                    .font(ChatTokens.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var promptCard: some View {
        Text(request.prompt)
            .font(ChatTokens.body)
            .foregroundStyle(theme.text)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var inputField: some View {
        TextField("Your response...", text: $value, axis: .vertical)
            .font(ChatTokens.body)
            .lineLimit(1 ... 6)
            .padding(12)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var submitButton: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            onSubmit()
            dismiss()
        } label: {
            Text("Submit")
                .font(ChatTokens.bodyBold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(submitBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(trimmedValue.isEmpty)
    }

    private var submitBackground: Color {
        trimmedValue.isEmpty
            ? ChatTokens.userBubble.opacity(0.4)
            : ChatTokens.userBubble
    }

    private var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
