import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// A question an employee asks with answers to pick: a white card, its title in bold, lettered
/// answers (A, B, C; typing the letter in the empty composer picks it too), ticks and Done when
/// several may be picked, and "Something else", which puts the cursor in the composer.
struct QuestionCard: View {
    let store: StoreOf<Workspace>
    let key: ConversationKey
    let question: ChatTimeline.Question

    var body: some View {
        let picked = store.state.picked(in: key, for: question.messageID)
        VStack(alignment: .leading, spacing: 4) {
            if let title = question.title {
                Text(title)
                    .font(DevysTypography.heading)
                    .foregroundStyle(DevysColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
            ForEach(Array(question.answers.enumerated()), id: \.offset) { index, answer in
                AnswerRow(
                    letter: ChatTimeline.Question.letter(index),
                    text: answer,
                    isPicked: picked.contains(answer),
                    showsCheck: question.pickMany
                ) {
                    store.send(.answerPicked(key, question.messageID, answer))
                }
            }
            AnswerRow(letter: nil, text: "Something else", isPicked: false, showsCheck: false) {
                store.send(.somethingElseTapped(key))
            }
            if question.pickMany {
                HStack {
                    Spacer()
                    Button("Done") { store.send(.answersDone(key, question.messageID)) }
                        .buttonStyle(DoneButtonStyle())
                        .disabled(picked.isEmpty)
                }
                .padding(.top, 4)
            }
        }
        .padding(10)
        .frame(maxWidth: 440, alignment: .leading)
        .background(DevysColors.sheet, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DevysColors.hairline, lineWidth: 1) }
        .devysElevation(.resting)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(question.title ?? "Answers")
    }
}

/// One answer: its letter in a small rounded square, the words, and a tick when picked.
private struct AnswerRow: View {
    let letter: String?
    let text: String
    let isPicked: Bool
    let showsCheck: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let letter {
                    Text(letter)
                        .font(.system(size: 11, weight: .semibold).monospaced())
                        .foregroundStyle(isPicked ? Color.white : DevysColors.ink2)
                        .frame(width: 22, height: 22)
                        .background(isPicked ? DevysColors.ink : DevysColors.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DevysColors.ink3)
                        .frame(width: 22, height: 22)
                }
                Text(text)
                    .font(DevysTypography.body)
                    .foregroundStyle(letter == nil ? DevysColors.ink3 : DevysColors.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if showsCheck {
                    Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isPicked ? DevysColors.ink : DevysColors.ink3.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(hovering ? DevysColors.sheetTint : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(letter.map { "\($0): \(text)" } ?? text)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}

/// The black Done of a pick-many card.
private struct DoneButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DevysTypography.control.weight(.semibold))
            .foregroundStyle(DevysColors.sheet)
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(DevysColors.ink.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.3), in: Capsule())
    }
}
