import Foundation

public struct TerminalTargetID: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var rawValue: UUID
    public var id: UUID { rawValue }

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct TerminalComposerTargetMetadata: Codable, Equatable, Sendable {
    public var cwdBasename: String

    public init(cwdBasename: String) {
        self.cwdBasename = cwdBasename
    }
}

public struct TerminalComposerChip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: TerminalComposerChipKind
    public var title: String
    public var subtitle: String?
    public var path: String?
    public var text: String?
    public var lineCount: Int?

    public init(
        id: UUID = UUID(),
        kind: TerminalComposerChipKind,
        title: String,
        subtitle: String? = nil,
        path: String? = nil,
        text: String? = nil,
        lineCount: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.text = text
        self.lineCount = lineCount
    }
}

public struct TerminalTargetState: Codable, Equatable, Identifiable, Sendable {
    public var id: TerminalTargetID
    public var metadata: TerminalComposerTargetMetadata
    public var draft: String
    public var chips: [TerminalComposerChip]

    public init(
        id: TerminalTargetID,
        metadata: TerminalComposerTargetMetadata,
        draft: String = "",
        chips: [TerminalComposerChip] = []
    ) {
        self.id = id
        self.metadata = metadata
        self.draft = draft
        self.chips = chips
    }
}

public struct TerminalComposerCollapsedState: Equatable, Sendable {
    public var hint: String

    public init(hint: String) {
        self.hint = hint
    }
}

public struct TerminalComposerFocusedState: Equatable, Sendable {
    public var isTargetSwitcherPresented: Bool

    public init(isTargetSwitcherPresented: Bool) {
        self.isTargetSwitcherPresented = isTargetSwitcherPresented
    }
}

public struct TerminalComposerTextRange: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    public static func insertion(at location: Int) -> TerminalComposerTextRange {
        TerminalComposerTextRange(location: location, length: 0)
    }

    func clamped(to text: String) -> TerminalComposerTextRange {
        let count = text.count
        let clampedLocation = min(max(0, location), count)
        let clampedLength = min(max(0, length), count - clampedLocation)
        return TerminalComposerTextRange(location: clampedLocation, length: clampedLength)
    }
}

public struct TerminalComposerDictatingState: Equatable, Sendable {
    public var baseDraft: String
    public var committedTranscript: String
    public var selectedRange: TerminalComposerTextRange
    public var transcript: String
    public var volatileTranscript: String

    public init(
        transcript: String,
        committedTranscript: String = "",
        volatileTranscript: String = "",
        baseDraft: String = "",
        selectedRange: TerminalComposerTextRange = .insertion(at: 0)
    ) {
        self.baseDraft = baseDraft
        self.committedTranscript = committedTranscript
        self.selectedRange = selectedRange
        self.transcript = transcript
        self.volatileTranscript = volatileTranscript
    }
}

public struct TerminalComposerSendingState: Equatable, Sendable {
    public var targetID: TerminalTargetID

    public init(targetID: TerminalTargetID) {
        self.targetID = targetID
    }
}

public enum TerminalComposerMode: Equatable, Sendable {
    case collapsed(TerminalComposerCollapsedState)
    case focused(TerminalComposerFocusedState)
    case dictating(TerminalComposerDictatingState)
    case sending(TerminalComposerSendingState)
}

public struct TerminalComposerChooseTargetState: Equatable, Sendable {
    public var reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

public enum TerminalComposerPresentation: Equatable, Sendable {
    case activeTarget
    case chooseTarget(TerminalComposerChooseTargetState)
}

public struct TerminalComposerSubmission: Equatable, Sendable {
    public var targetID: TerminalTargetID
    public var text: String

    public init(targetID: TerminalTargetID, text: String) {
        self.targetID = targetID
        self.text = text
    }
}

public enum TerminalComposerFocusDestination: Equatable, Sendable {
    case composer
    case terminal
}

@MainActor
public final class TerminalComposerModel: ObservableObject {
    @Published public internal(set) var mode: TerminalComposerMode
    @Published public internal(set) var presentation: TerminalComposerPresentation = .activeTarget
    @Published public internal(set) var activeTargetID: TerminalTargetID?
    @Published public internal(set) var visibleTargetIDs: [TerminalTargetID] = []
    @Published public internal(set) var targets: [TerminalTargetState] = []

    public init() {
        mode = .collapsed(TerminalComposerCollapsedState(hint: "Choose a terminal"))
    }

    public var activeTarget: TerminalTargetState? {
        guard let activeTargetID else { return nil }
        return targets.first { $0.id == activeTargetID }
    }

    public var activeDraft: String {
        activeTarget?.draft ?? ""
    }

    public var activeChips: [TerminalComposerChip] {
        activeTarget?.chips ?? []
    }

    public var isFocused: Bool {
        switch mode {
        case .focused, .dictating, .sending:
            true
        case .collapsed:
            false
        }
    }

    public var chrome: TerminalComposerChrome {
        TerminalComposerChrome(visibleTargetCount: visibleTargetIDs.count)
    }

    public func registerTarget(
        id: TerminalTargetID,
        metadata: TerminalComposerTargetMetadata,
        isActive: Bool = false
    ) {
        if let index = targets.firstIndex(where: { $0.id == id }) {
            targets[index].metadata = metadata
        } else {
            targets.append(TerminalTargetState(id: id, metadata: metadata))
        }
        if isActive || activeTargetID == nil {
            activateTarget(id)
        }
        if !visibleTargetIDs.contains(id) {
            visibleTargetIDs.append(id)
        }
        refreshCollapsedHint()
    }

    public func setVisibleTargetIDs(_ ids: [TerminalTargetID]) {
        visibleTargetIDs = ids
        if let activeTargetID, !ids.contains(activeTargetID) {
            activateMostRecentVisibleTarget()
        }
    }

    public func activateTarget(_ id: TerminalTargetID) {
        guard targets.contains(where: { $0.id == id }) else {
            presentChooseTarget(reason: "Choose a terminal")
            return
        }
        activeTargetID = id
        presentation = .activeTarget
        refreshCollapsedHint()
    }

    public func updateMetadata(for id: TerminalTargetID, metadata: TerminalComposerTargetMetadata) {
        guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
        targets[index].metadata = metadata
        refreshCollapsedHint()
    }

    public func updateActiveDraft(_ draft: String) {
        guard let index = activeTargetIndex() else {
            presentChooseTarget(reason: "Choose a terminal before composing")
            return
        }
        targets[index].draft = draft
        if !draft.isEmpty {
            focus()
        }
    }

    public func appendNewlineToActiveDraft() {
        updateActiveDraft(activeDraft + "\n")
    }

    public func addChip(_ chip: TerminalComposerChip, to id: TerminalTargetID? = nil) {
        guard let index = targetIndex(id) else {
            presentChooseTarget(reason: "Choose a terminal before attaching")
            return
        }
        targets[index].chips.append(chip)
        focus()
    }

    public func removeChip(id chipID: TerminalComposerChip.ID, from id: TerminalTargetID? = nil) {
        guard let index = targetIndex(id) else { return }
        targets[index].chips.removeAll { $0.id == chipID }
        if targets[index].draft.isEmpty, targets[index].chips.isEmpty {
            mode = .collapsed(TerminalComposerCollapsedState(hint: collapsedHint()))
        }
    }

    public func attachFileURLs(_ urls: [URL], to id: TerminalTargetID? = nil) {
        for url in urls {
            addChip(.fileSystemItem(url: url), to: id)
        }
    }

    @discardableResult
    public func ingestPaste(
        _ text: String,
        settings: TerminalComposerSmartPasteSettings = TerminalComposerSmartPasteSettings()
    ) -> TerminalComposerPasteResult {
        guard !text.isEmpty else { return .ignored }
        let lineCount = TerminalComposerChip.lineCount(in: text)
        if lineCount > settings.inlineLineThreshold {
            let chip = TerminalComposerChip.paste(text: text)
            addChip(chip)
            return .attached(chip)
        }
        updateActiveDraft(activeDraft + text)
        return .insertedInline(text)
    }

    @discardableResult
    public func captureSelection(_ text: String) -> TerminalComposerChip? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let chip = TerminalComposerChip.selection(text: text)
        addChip(chip)
        return chip
    }

    public func startDictation(selection: TerminalComposerTextRange? = nil) {
        guard let index = activeTargetIndex() else {
            presentChooseTarget(reason: "Choose a terminal before dictating")
            return
        }
        let baseDraft = targets[index].draft
        let selectedRange = (selection ?? .insertion(at: baseDraft.count)).clamped(to: baseDraft)
        mode = .dictating(
            TerminalComposerDictatingState(
                transcript: "",
                baseDraft: baseDraft,
                selectedRange: selectedRange
            )
        )
    }

    public func updateDictationTranscript(_ transcript: String) {
        updateDictationTranscript(transcript, isFinal: false)
    }

    public func updateDictationTranscript(_ transcript: String, isFinal: Bool) {
        guard case .dictating(var state) = mode,
              let index = activeTargetIndex()
        else { return }
        let normalizedTranscript = Self.normalizedSpeechPart(transcript)
        guard !normalizedTranscript.isEmpty else { return }

        if isFinal {
            let uncommittedTranscript = Self.uncommittedSpeechPart(
                from: transcript,
                after: state.committedTranscript
            )
            state.committedTranscript = Self.joinSpeechParts(state.committedTranscript, uncommittedTranscript)
            state.volatileTranscript = ""
        } else {
            state.volatileTranscript = Self.uncommittedSpeechPart(
                from: transcript,
                after: state.committedTranscript
            )
        }
        state.transcript = Self.joinSpeechParts(state.committedTranscript, state.volatileTranscript)
        mode = .dictating(state)
        targets[index].draft = TerminalComposerModel.replacingSelection(
            in: state.baseDraft,
            range: state.selectedRange,
            replacement: state.transcript
        )
    }

    public func finishDictation() {
        guard case .dictating = mode else { return }
        mode = .focused(TerminalComposerFocusedState(isTargetSwitcherPresented: false))
    }

    public func cancelDictation() {
        guard case .dictating(let state) = mode,
              let index = activeTargetIndex()
        else { return }
        targets[index].draft = state.baseDraft
        mode = .focused(TerminalComposerFocusedState(isTargetSwitcherPresented: false))
    }

    public func focus() {
        if activeTargetID == nil {
            presentChooseTarget(reason: "Choose a terminal before composing")
            return
        }
        mode = .focused(TerminalComposerFocusedState(isTargetSwitcherPresented: false))
    }

    public func commandL() -> TerminalComposerFocusDestination {
        focus()
        return .composer
    }

    public func escape() -> TerminalComposerFocusDestination {
        if case .dictating = mode {
            cancelDictation()
            return .composer
        }
        guard case .collapsed = mode else {
            mode = .collapsed(TerminalComposerCollapsedState(hint: collapsedHint()))
            return .terminal
        }
        return .terminal
    }

    public func submitActiveDraft() -> TerminalComposerSubmission? {
        submitActiveDraft(serializationStyle: .shell)
    }

    public func presentTargetSwitcher() {
        mode = .focused(TerminalComposerFocusedState(isTargetSwitcherPresented: true))
    }

    func activeTargetIndex() -> Int? {
        guard let activeTargetID else { return nil }
        return targets.firstIndex { $0.id == activeTargetID }
    }

    func targetIndex(_ id: TerminalTargetID?) -> Int? {
        if let id {
            return targets.firstIndex { $0.id == id }
        }
        return activeTargetIndex()
    }

    private func activateMostRecentVisibleTarget() {
        guard let id = visibleTargetIDs.last,
              targets.contains(where: { $0.id == id })
        else {
            activeTargetID = nil
            presentChooseTarget(reason: "Choose a terminal")
            return
        }
        activateTarget(id)
    }

    func presentChooseTarget(reason: String) {
        activeTargetID = nil
        presentation = .chooseTarget(TerminalComposerChooseTargetState(reason: reason))
        mode = .focused(TerminalComposerFocusedState(isTargetSwitcherPresented: true))
    }

    private func refreshCollapsedHint() {
        guard case .collapsed = mode else { return }
        mode = .collapsed(TerminalComposerCollapsedState(hint: collapsedHint()))
    }

    private static func replacingSelection(
        in text: String,
        range: TerminalComposerTextRange,
        replacement: String
    ) -> String {
        let clamped = range.clamped(to: text)
        let start = text.index(text.startIndex, offsetBy: clamped.location)
        let end = text.index(start, offsetBy: clamped.length)
        var result = text
        result.replaceSubrange(start..<end, with: replacement)
        return result
    }

    private static func joinSpeechParts(_ parts: String...) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func uncommittedSpeechPart(from transcript: String, after committedTranscript: String) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommittedTranscript = committedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return "" }
        guard !trimmedCommittedTranscript.isEmpty else { return trimmedTranscript }

        let normalizedTranscript = normalizedSpeechPart(trimmedTranscript)
        let normalizedCommittedTranscript = normalizedSpeechPart(trimmedCommittedTranscript)
        if normalizedTranscript.isEmpty
            || normalizedTranscript == normalizedCommittedTranscript
            || normalizedSpeechPartHasSuffix(normalizedCommittedTranscript, suffix: normalizedTranscript)
        {
            return ""
        }

        if trimmedTranscript.lowercased().hasPrefix(trimmedCommittedTranscript.lowercased()) {
            let suffixStart = trimmedTranscript.index(
                trimmedTranscript.startIndex,
                offsetBy: trimmedCommittedTranscript.count
            )
            return String(trimmedTranscript[suffixStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmedTranscript
    }

    private static func normalizedSpeechPart(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func normalizedSpeechPartHasSuffix(_ text: String, suffix: String) -> Bool {
        let words = text.split(separator: " ")
        let suffixWords = suffix.split(separator: " ")
        guard !suffixWords.isEmpty, words.count >= suffixWords.count else { return false }
        return words.suffix(suffixWords.count).elementsEqual(suffixWords)
    }

    func collapsedHint() -> String {
        guard let basename = activeTarget?.metadata.cwdBasename, !basename.isEmpty else {
            return "Choose a terminal"
        }
        return "Type a command in \(basename)"
    }
}

public struct TerminalComposerChrome: Equatable, Sendable {
    public var visibleTargetCount: Int

    public var usesFloatingTreatment: Bool {
        visibleTargetCount > 1
    }

    public init(visibleTargetCount: Int) {
        self.visibleTargetCount = visibleTargetCount
    }
}
