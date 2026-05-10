import TerminalComposer
import XCTest

@MainActor
final class TerminalComposerTests: XCTestCase {
    func testCommandLFocusesComposerForActiveTarget() {
        let model = TerminalComposerModel()
        let targetID = TerminalTargetID()

        model.registerTarget(
            id: targetID,
            metadata: TerminalComposerTargetMetadata(cwdBasename: "devys"),
            isActive: true
        )

        XCTAssertEqual(model.commandL(), .composer)
        XCTAssertEqual(model.activeTargetID, targetID)
        XCTAssertTrue(model.isFocused)
    }

    func testEscapeRoutesFocusToTerminalWithoutLosingDraft() {
        let model = TerminalComposerModel()
        let targetID = TerminalTargetID()
        model.registerTarget(
            id: targetID,
            metadata: TerminalComposerTargetMetadata(cwdBasename: "devys"),
            isActive: true
        )
        model.updateActiveDraft("status")

        XCTAssertEqual(model.escape(), .terminal)
        XCTAssertEqual(model.activeDraft, "status")
        XCTAssertFalse(model.isFocused)
    }

    func testPerTargetDraftsSurviveTargetSwitches() {
        let model = TerminalComposerModel()
        let one = TerminalTargetID()
        let two = TerminalTargetID()
        let three = TerminalTargetID()

        model.registerTarget(id: one, metadata: metadata("one"), isActive: true)
        model.updateActiveDraft("first")

        model.registerTarget(id: two, metadata: metadata("two"))
        model.activateTarget(two)
        model.updateActiveDraft("second")

        model.registerTarget(id: three, metadata: metadata("three"))
        model.activateTarget(three)
        model.updateActiveDraft("third")

        model.activateTarget(one)
        XCTAssertEqual(model.activeDraft, "first")

        model.activateTarget(two)
        XCTAssertEqual(model.activeDraft, "second")

        model.activateTarget(three)
        XCTAssertEqual(model.activeDraft, "third")
    }

    func testSubmitRequiresActiveTargetAndPresentsChooseTarget() {
        let model = TerminalComposerModel()
        model.updateActiveDraft("status")

        XCTAssertNil(model.submitActiveDraft())
        XCTAssertEqual(
            model.presentation,
            .chooseTarget(TerminalComposerChooseTargetState(reason: "Choose a terminal before sending"))
        )
    }

    func testPlainTextSubmitReturnsPayloadAndClearsDraft() {
        let model = TerminalComposerModel()
        let targetID = TerminalTargetID()
        model.registerTarget(
            id: targetID,
            metadata: TerminalComposerTargetMetadata(cwdBasename: "devys"),
            isActive: true
        )
        model.updateActiveDraft("git status\n")

        let submission = model.submitActiveDraft()

        XCTAssertEqual(submission, TerminalComposerSubmission(targetID: targetID, text: "git status"))
        XCTAssertEqual(model.activeDraft, "")
        XCTAssertFalse(model.isFocused)
    }

    func testShiftReturnNewlineMutationIsModeledSeparatelyFromSubmit() {
        let model = TerminalComposerModel()
        model.registerTarget(
            id: TerminalTargetID(),
            metadata: TerminalComposerTargetMetadata(cwdBasename: "devys"),
            isActive: true
        )
        model.updateActiveDraft("first")
        model.appendNewlineToActiveDraft()
        model.updateActiveDraft(model.activeDraft + "second")

        XCTAssertEqual(model.activeDraft, "first\nsecond")
    }

    func testFileAndFolderAttachmentsUseSpecificChipKinds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("Sources", isDirectory: true)
        let file = root.appendingPathComponent("README.md")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = registeredModel()
        model.attachFileURLs([folder, file])

        XCTAssertEqual(model.activeChips.map(\.kind), [.folder, .file])
        XCTAssertEqual(model.activeChips.map(\.path), [folder.path, file.path])
    }

    func testFileChipTitleIsBareFilenameAndSubtitleHasFileSize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = root.appendingPathComponent("README.md")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = registeredModel()
        model.attachFileURLs([file])

        let chip = try XCTUnwrap(model.activeChips.first)
        XCTAssertEqual(chip.title, "README.md")
        XCTAssertFalse(chip.title.contains("File · "))
        let subtitle = try XCTUnwrap(chip.subtitle)
        XCTAssertTrue(
            subtitle.contains("byte") || subtitle.contains("KB"),
            "Expected file size subtitle, got \(subtitle)"
        )
    }

    func testFolderChipTitleIsBareFolderNameAndSubtitleHasItemCount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "a".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: folder.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = registeredModel()
        model.attachFileURLs([folder])

        let chip = try XCTUnwrap(model.activeChips.first)
        XCTAssertEqual(chip.title, "Sources")
        XCTAssertFalse(chip.title.contains("Folder · "))
        XCTAssertEqual(chip.subtitle, "2 items")
    }

    func testSmartPasteCreatesChipOnlyAboveThreshold() {
        let model = registeredModel()

        let inline = model.ingestPaste("one\ntwo", settings: TerminalComposerSmartPasteSettings(inlineLineThreshold: 4))
        XCTAssertEqual(inline, .insertedInline("one\ntwo"))
        XCTAssertEqual(model.activeDraft, "one\ntwo")
        XCTAssertEqual(model.activeChips, [])

        let attached = model.ingestPaste(
            "1\n2\n3\n4\n5",
            settings: TerminalComposerSmartPasteSettings(inlineLineThreshold: 4)
        )
        guard case .attached(let chip) = attached else {
            return XCTFail("Expected a paste chip")
        }
        XCTAssertEqual(chip.kind, .paste)
        XCTAssertEqual(chip.title, "Paste · 5 lines")
        XCTAssertEqual(model.activeChips, [chip])
    }

    func testRemovingLastChipCollapsesEmptyComposer() {
        let model = registeredModel()
        let chip = TerminalComposerChip.paste(text: "1\n2\n3\n4\n5")
        model.addChip(chip)

        model.removeChip(id: chip.id)

        XCTAssertEqual(model.activeChips, [])
        XCTAssertFalse(model.isFocused)
    }

    func testTerminalSelectionCaptureFocusesComposerAndStoresText() {
        let model = registeredModel()

        let chip = model.captureSelection("selected output")

        XCTAssertEqual(chip?.kind, .selection)
        XCTAssertEqual(model.activeChips.first?.text, "selected output")
        XCTAssertTrue(model.isFocused)
    }

    func testShellSerializationQuotesPathsAndUsesHeredocs() {
        let model = registeredModel()
        model.updateActiveDraft("cat")
        model.addChip(TerminalComposerChip(kind: .file, title: "File", path: "/tmp/has space.txt"))
        model.addChip(.paste(text: "first\nsecond"))

        let submission = model.submitActiveDraft(serializationStyle: .shell)

        XCTAssertEqual(submission?.text.contains("cat '/tmp/has space.txt'"), true)
        XCTAssertEqual(submission?.text.contains("cat <<'DEVYS_PASTE_"), true)
        XCTAssertEqual(submission?.text.hasSuffix("\r"), false)
        XCTAssertEqual(model.activeChips, [])
    }

    func testAgentSerializersRenderStyleSpecificReferences() {
        let file = TerminalComposerChip(kind: .file, title: "File", path: "/tmp/a.swift")
        let paste = TerminalComposerChip.paste(text: "explain this")

        let codex = TerminalComposerSerializer.serialize(draft: "review", chips: [file, paste], style: .codex)
        let claude = TerminalComposerSerializer.serialize(draft: "review", chips: [file, paste], style: .claudeCode)

        XCTAssertTrue(codex.contains("@/tmp/a.swift"))
        XCTAssertTrue(codex.contains("<codex-paste lines=\"1\">"))
        XCTAssertTrue(claude.contains("/attach /tmp/a.swift"))
        XCTAssertTrue(claude.contains("<claude-paste lines=\"1\">"))
    }

    func testComposerAndProductRoundedRectanglesUseDesignSystemRadius() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoots = [
            packageRoot.appendingPathComponent("Sources/TerminalComposer", isDirectory: true),
            packageRoot.appendingPathComponent("Sources/TerminalProduct", isDirectory: true),
        ]
        let sourceFiles = try sourceRoots.flatMap(swiftFiles(in:))

        for file in sourceFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated()
                where line.contains("RoundedRectangle(cornerRadius:")
            {
                let location = "\(file.path):\(index + 1)"
                XCTAssertTrue(line.contains("Spacing.radius"), "\(location) must use Spacing.radius")
                XCTAssertTrue(line.contains("style: .continuous"), "\(location) must use continuous corners")
            }
        }
    }

    func testComposerTextInputUsesControlledAppKitTextViewOnMac() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let textInputFile = packageRoot.appendingPathComponent(
            "Sources/TerminalComposer/TerminalComposerTextInput.swift"
        )
        let contents = try String(contentsOf: textInputFile, encoding: .utf8)

        XCTAssertTrue(contents.contains("TerminalComposerMacTextInput("))
        XCTAssertTrue(contents.contains("private final class TerminalComposerNSTextView: NSTextView"))
        XCTAssertTrue(contents.contains("override func keyDown(with event: NSEvent)"))
        XCTAssertTrue(contents.contains("override func mouseDown(with event: NSEvent)"))
        XCTAssertTrue(contents.contains("onFocus()"))
        XCTAssertTrue(contents.contains("textView.string = text"))
        XCTAssertTrue(contents.contains("text.wrappedValue = textView.string"))
        XCTAssertFalse(contents.contains("NSEvent.addLocalMonitorForEvents(matching: .keyDown)"))
    }

    func testComposerViewReturnsFocusAndResetsEditorAfterSubmit() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let composerViewFile = packageRoot.appendingPathComponent(
            "Sources/TerminalComposer/TerminalComposerView.swift"
        )
        let contents = try String(contentsOf: composerViewFile, encoding: .utf8)

        XCTAssertTrue(contents.contains("textInputResetID = UUID()"))
        XCTAssertTrue(contents.contains("onTerminalFocusRequest()"))
    }

    func testComposerViewShowsMinimalSerializationModeLabel() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let composerViewFile = packageRoot.appendingPathComponent(
            "Sources/TerminalComposer/TerminalComposerView.swift"
        )
        let contents = try String(contentsOf: composerViewFile, encoding: .utf8)

        XCTAssertTrue(contents.contains("Text(composerModeLabel)"))
        XCTAssertTrue(contents.contains("case .shell:"))
        XCTAssertTrue(contents.contains("\"Shell\""))
        XCTAssertTrue(contents.contains("case .codex:"))
        XCTAssertTrue(contents.contains("\"Codex\""))
        XCTAssertTrue(contents.contains("case .claudeCode:"))
        XCTAssertTrue(contents.contains("\"Claude\""))
    }

    private func metadata(_ cwdBasename: String) -> TerminalComposerTargetMetadata {
        TerminalComposerTargetMetadata(cwdBasename: cwdBasename)
    }

    private func registeredModel() -> TerminalComposerModel {
        let model = TerminalComposerModel()
        model.registerTarget(
            id: TerminalTargetID(),
            metadata: TerminalComposerTargetMetadata(cwdBasename: "devys"),
            isActive: true
        )
        return model
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "swift" else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }
}
