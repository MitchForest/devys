import Foundation

public extension TerminalComposerModel {
    func submitActiveDraft(
        serializationStyle: TerminalComposerSerializationStyle
    ) -> TerminalComposerSubmission? {
        guard let targetID = activeTargetID,
              let index = activeTargetIndex()
        else {
            presentChooseTarget(reason: "Choose a terminal before sending")
            return nil
        }
        let trimmed = targets[index].draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let chips = targets[index].chips
        guard !trimmed.isEmpty || !chips.isEmpty else {
            mode = .collapsed(TerminalComposerCollapsedState(hint: collapsedHint()))
            return nil
        }
        targets[index].draft = ""
        targets[index].chips = []
        let serialized = TerminalComposerSerializer.serialize(
            draft: trimmed,
            chips: chips,
            style: serializationStyle
        )
        mode = .collapsed(TerminalComposerCollapsedState(hint: collapsedHint()))
        return TerminalComposerSubmission(targetID: targetID, text: serialized)
    }
}
