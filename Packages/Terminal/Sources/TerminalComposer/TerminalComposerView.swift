import SwiftUI
import UI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

public struct TerminalComposerView: View {
    @Environment(\.theme) private var theme

    @ObservedObject private var model: TerminalComposerModel
    private let serializationStyle: TerminalComposerSerializationStyle
    private let smartPasteSettings: TerminalComposerSmartPasteSettings
    private let dictationKey: TerminalComposerDictationKey
    private let speechService: any TerminalComposerSpeechService
    private let onSubmit: (TerminalComposerSubmission) -> Void
    private let onTerminalFocusRequest: () -> Void
    @State private var speechCapture: (any TerminalComposerSpeechCapture)?
    @State private var dictationTask: Task<Void, Never>?
    @State private var waveformLevel: Double = 0
    @State private var isDropTargeted = false
    @State private var textInputResetID = UUID()

    public init(
        model: TerminalComposerModel,
        serializationStyle: TerminalComposerSerializationStyle = .shell,
        smartPasteSettings: TerminalComposerSmartPasteSettings = TerminalComposerSmartPasteSettings(),
        dictationKey: TerminalComposerDictationKey = .function,
        speechService: any TerminalComposerSpeechService = DefaultTerminalComposerSpeechService(),
        onSubmit: @escaping (TerminalComposerSubmission) -> Void,
        onTerminalFocusRequest: @escaping () -> Void
    ) {
        self.model = model
        self.serializationStyle = serializationStyle
        self.smartPasteSettings = smartPasteSettings
        self.dictationKey = dictationKey
        self.speechService = speechService
        self.onSubmit = onSubmit
        self.onTerminalFocusRequest = onTerminalFocusRequest
    }

    public var body: some View {
        composerSurface
            .frame(maxWidth: TerminalComposerLayout.maxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.comfortable)
            .padding(.bottom, Spacing.comfortable)
            .background(
                TerminalComposerPushToTalkBridge(
                    isComposerActive: model.isFocused,
                    isDictating: isDictating,
                    dictationKey: dictationKey,
                    onBegin: beginDictation,
                    onCommit: finishDictation,
                    onCancel: cancelDictation
                )
            )
            .onDisappear {
                stopSpeechCapture()
            }
    }

    private var composerSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            attachmentsPreviewStrip
            composerInputArea
            keyboardHintRow
        }
        .vibrantSurface(.overlay)
        .overlay {
            ZStack {
                composerFocusOverlay

                if isDropTargeted {
                    TerminalComposerDropHighlight()
                        .transition(.opacity)
                }
            }
            .animation(Animations.micro, value: isDropTargeted)
        }
        .animation(Animations.micro, value: model.isFocused)
        .onDrop(
            of: TerminalComposerDropTypes.all,
            isTargeted: $isDropTargeted,
            perform: handleDrop
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var composerFocusOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
        if model.isFocused {
            shape
                .strokeBorder(theme.borderFocus, lineWidth: 1)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
        if isDictating {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 2)
                    .padding(.vertical, Spacing.normal)
                Spacer(minLength: 0)
            }
            .clipShape(shape)
            .transition(.opacity)
        }
    }

    private var activeDraftBinding: Binding<String> {
        Binding(
            get: { model.activeDraft },
            set: { model.updateActiveDraft($0) }
        )
    }

    @ViewBuilder
    private var attachmentsPreviewStrip: some View {
        if !model.activeChips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.normal) {
                    ForEach(model.activeChips) { chip in
                        AttachmentChipView(chip: chip) {
                            model.removeChip(id: chip.id)
                        }
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Spacing.relaxed)
                .padding(.top, Spacing.comfortable)
                .padding(.bottom, Spacing.normal)
                .animation(Animations.micro, value: model.activeChips.map(\.id))
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }

    private var composerInputArea: some View {
        DevysGlassContainer(spacing: Spacing.normal) {
            HStack(alignment: .bottom, spacing: Spacing.normal) {
                ComposerIconButton(
                    systemName: "plus",
                    accessibilityLabel: "Attach files",
                    isActive: !model.activeChips.isEmpty,
                    action: presentAttachmentPicker
                )
                .padding(.bottom, 2)

                textField
                    .frame(minHeight: TerminalComposerLayout.iconSize)

                actionButtons
                    .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, Spacing.relaxed)
        .padding(.vertical, Spacing.comfortable)
    }

    private var textField: some View {
        ZStack(alignment: .topLeading) {
            if model.activeDraft.isEmpty {
                Text(collapsedPlaceholder)
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.leading, TerminalComposerLayout.textEditorLeadingInset)
                    .padding(.top, TerminalComposerLayout.textEditorTopInset)
                    .allowsHitTesting(false)
            }

            TerminalComposerTextInput(
                text: activeDraftBinding,
                isFocused: model.isFocused,
                minHeight: TerminalComposerLayout.minTextHeight,
                maxHeight: TerminalComposerLayout.maxTextHeight,
                onFocus: model.focus,
                onSubmit: submit,
                onNewline: model.appendNewlineToActiveDraft,
                onEscape: handleEscape
            )
            .id(textInputResetID)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: Spacing.normal) {
            if isDictating {
                TerminalComposerInlineWaveformView(level: waveformLevel)
                    .transition(.opacity)
            }

            ComposerIconButton(
                systemName: isDictating ? "mic.fill" : "mic",
                accessibilityLabel: isDictating ? "Stop dictation" : "Start dictation",
                isActive: isDictating,
                action: toggleDictation
            )

            ComposerIconButton(
                systemName: "return",
                accessibilityLabel: "Send",
                isEnabled: hasSubmittableContent,
                action: submit
            )
        }
    }

    private var keyboardHintRow: some View {
        HStack(spacing: Spacing.comfortable) {
            Spacer(minLength: 0)
            ForEach(activeKeyboardHints, id: \.id) { hint in
                HStack(spacing: 4) {
                    Text(hint.key)
                        .font(Typography.micro.weight(.semibold))
                    Text(hint.label)
                        .font(Typography.micro)
                }
                .foregroundStyle(theme.textSecondary)
            }
            Text(composerModeLabel)
                .font(Typography.micro.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, Spacing.relaxed)
        .padding(.bottom, Spacing.normal)
        .padding(.top, Spacing.tight)
    }

    private var activeKeyboardHints: [TerminalComposerKeyboardHint] {
        if isDictating {
            return [TerminalComposerKeyboardHint(key: "Esc", label: "cancel")]
        }
        if model.isFocused {
            if hasSubmittableContent {
                return [
                    TerminalComposerKeyboardHint(key: "⏎", label: "send"),
                    TerminalComposerKeyboardHint(key: "⇧⏎", label: "newline"),
                    TerminalComposerKeyboardHint(key: "Esc", label: "exit"),
                ]
            }
            return [
                TerminalComposerKeyboardHint(key: "⇧⏎", label: "newline"),
                TerminalComposerKeyboardHint(key: dictationKeyLabel, label: "dictate"),
                TerminalComposerKeyboardHint(key: "Esc", label: "exit"),
            ]
        }
        return [TerminalComposerKeyboardHint(key: "⌘L", label: "compose")]
    }

    private var composerModeLabel: String {
        switch serializationStyle {
        case .shell:
            "Shell"
        case .codex:
            "Codex"
        case .claudeCode:
            "Claude"
        }
    }

    private var dictationKeyLabel: String {
        switch dictationKey {
        case .function:
            "Fn"
        case .control:
            "⌃"
        case .option:
            "⌥"
        }
    }

    private var isDictating: Bool {
        if case .dictating = model.mode {
            return true
        }
        return false
    }

    private var collapsedPlaceholder: String {
        switch model.mode {
        case .collapsed(let state):
            state.hint
        case .focused, .sending:
            collapsedFallbackHint
        case .dictating:
            "Listening…"
        }
    }

    private var collapsedFallbackHint: String {
        guard let basename = model.activeTarget?.metadata.cwdBasename, !basename.isEmpty else {
            return "Type a command"
        }
        return "Type a command in \(basename)"
    }

    private var hasSubmittableContent: Bool {
        !model.activeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.activeChips.isEmpty
    }

    private func submit() {
        if let submission = model.submitActiveDraft(serializationStyle: serializationStyle) {
            textInputResetID = UUID()
            onSubmit(submission)
            onTerminalFocusRequest()
        }
    }

    private func presentAttachmentPicker() {
        model.focus()
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Attach"
        if panel.runModal() == .OK {
            model.attachFileURLs(panel.urls)
        }
        #endif
    }
}

private extension TerminalComposerView {
    func beginDictation() {
        guard !isDictating else { return }
        model.focus()
        model.startDictation(selection: .insertion(at: model.activeDraft.count))
        waveformLevel = 0.16
        dictationTask?.cancel()
        dictationTask = Task { @MainActor in
            do {
                let capture = try await speechService.startTranscription { event in
                    waveformLevel = max(event.audioLevel, event.text.isEmpty ? 0.16 : 0.30)
                    if !event.text.isEmpty {
                        model.updateDictationTranscript(event.text, isFinal: event.isFinal)
                    }
                }
                if Task.isCancelled {
                    await capture.stop()
                } else {
                    speechCapture = capture
                }
            } catch {
                model.cancelDictation()
                waveformLevel = 0
            }
        }
    }

    func toggleDictation() {
        if isDictating {
            finishDictation()
        } else {
            beginDictation()
        }
    }

    private func finishDictation() {
        guard isDictating else { return }
        stopSpeechCapture()
        model.finishDictation()
        waveformLevel = 0
    }

    private func cancelDictation() {
        guard isDictating else { return }
        stopSpeechCapture()
        model.cancelDictation()
        waveformLevel = 0
    }

    private func handleEscape() {
        if isDictating {
            cancelDictation()
            return
        }
        if model.escape() == .terminal {
            onTerminalFocusRequest()
        }
    }

    private func stopSpeechCapture() {
        dictationTask?.cancel()
        dictationTask = nil
        let capture = speechCapture
        speechCapture = nil
        Task { @MainActor in
            await capture?.stop()
        }
    }
}

private extension TerminalComposerView {
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            ingest(provider: provider)
        }
        return true
    }

    private func ingest(provider: NSItemProvider) {
        if provider.canLoadObject(ofClass: URL.self) {
            ingestFileURL(from: provider)
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            ingestImageData(from: provider)
        } else if provider.canLoadObject(ofClass: NSString.self) {
            ingestText(from: provider)
        }
    }

    private func ingestFileURL(from provider: NSItemProvider) {
        _ = provider.loadObject(ofClass: URL.self) { object, _ in
            guard let url = object else { return }
            Task { @MainActor in
                model.attachFileURLs([url])
            }
        }
    }

    private func ingestImageData(from provider: NSItemProvider) {
        let typeIdentifier = UTType.image.identifier
        let suggestedExtension = Self.suggestedExtension(for: provider, fallback: "png")
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data else { return }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("devys-attachment-\(UUID().uuidString).\(suggestedExtension)")
            do {
                try data.write(to: tempURL, options: .atomic)
            } catch {
                return
            }
            Task { @MainActor in
                model.attachFileURLs([tempURL])
            }
        }
    }

    private func ingestText(from provider: NSItemProvider) {
        let settings = smartPasteSettings
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let nsString = object as? NSString else { return }
            let text = nsString as String
            Task { @MainActor in
                _ = model.ingestPaste(text, settings: settings)
            }
        }
    }

    private static func suggestedExtension(for provider: NSItemProvider, fallback: String) -> String {
        if let name = provider.suggestedName,
           case let ext = (name as NSString).pathExtension,
           !ext.isEmpty {
            return ext
        }
        for identifier in provider.registeredTypeIdentifiers {
            if let type = UTType(identifier), let preferred = type.preferredFilenameExtension {
                return preferred
            }
        }
        return fallback
    }
}
