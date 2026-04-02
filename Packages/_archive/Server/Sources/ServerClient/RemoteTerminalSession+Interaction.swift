import Foundation

public extension RemoteTerminalSession {
    func clearOutputPreview() {
        clearOutputPreviewState()
    }

    func scrollViewUp(_ lines: Int, allowAltScreen: Bool = true) async {
        let update = await model.scrollViewUp(lines, allowAltScreen: allowAltScreen)
        applyRenderUpdate(update)
    }

    func scrollViewDown(_ lines: Int, allowAltScreen: Bool = true) async {
        let update = await model.scrollViewDown(lines, allowAltScreen: allowAltScreen)
        applyRenderUpdate(update)
    }

    func scrollToTop(allowAltScreen: Bool = true) async {
        let update = await model.scrollToTop(allowAltScreen: allowAltScreen)
        applyRenderUpdate(update)
    }

    func scrollToBottom(allowAltScreen: Bool = true) async {
        let update = await model.scrollToBottom(allowAltScreen: allowAltScreen)
        applyRenderUpdate(update)
    }

    func beginSelection(row: Int, col: Int) async {
        let update = await model.beginSelection(row: row, col: col)
        applyRenderUpdate(update)
    }

    func updateSelection(row: Int, col: Int) async {
        let update = await model.updateSelection(row: row, col: col)
        applyRenderUpdate(update)
    }

    func finishSelection() async {
        let update = await model.finishSelection()
        applyRenderUpdate(update)
    }

    func clearSelection() async {
        let update = await model.clearSelection()
        applyRenderUpdate(update)
    }

    func selectWord(row: Int, col: Int) async {
        guard let update = await model.selectWord(row: row, col: col) else { return }
        applyRenderUpdate(update)
    }

    func selectionText() async -> String? {
        await model.selectionText()
    }

    func screenText() async -> String {
        await model.screenText()
    }
}
