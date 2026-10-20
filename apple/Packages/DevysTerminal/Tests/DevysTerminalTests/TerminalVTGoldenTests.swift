import Foundation
import TerminalCore
import TerminalVT
import Testing

/// VT golden transcripts (P0-016, extending the P0-011 set): byte-exact
/// escape-sequence fixtures replayed through the real libghostty-vt
/// engine and asserted cell-for-cell or line-for-line. No fallback
/// engine exists; these run identically on macOS and iOS Simulator.
@Suite
struct TerminalVTGoldenTests {
    private static let dark = GhosttyTerminalAppearance.defaultDark

    private func padded(_ text: String, cols: Int) -> String {
        text + String(repeating: " ", count: max(0, cols - text.count))
    }

    // MARK: - Colors / SGR

    @Test
    func sgrTranscriptProjectsGoldenCells() async throws {
        let runtime = try TerminalVTRuntime(cols: 6, rows: 2, appearance: .defaultDark)

        let result = await runtime.write(
            Data("\u{1B}[31mAB\u{1B}[0m\u{1B}[1mC\u{1B}[0mあ".utf8)
        )

        let foreground = Self.dark.foreground.packedRGB
        let background = Self.dark.background.packedRGB
        let red = GhosttyTerminalAppearance.ghosttyDarkPalette[1].packedRGB
        let projection = result.surfaceUpdate.frameProjection
        let row = try #require(projection.row(at: 0))
        let golden = [
            cell(0, "A", foreground: red, background: background),
            cell(1, "B", foreground: red, background: background),
            cell(2, "C", foreground: foreground, background: background, isBold: true),
            cell(3, "あ", foreground: foreground, background: background, isWide: true),
            continuationCell(4, foreground: foreground, background: background),
            cell(5, " ", foreground: foreground, background: background)
        ]

        #expect(row.cells == golden)
        #expect(projection.defaultForegroundPacked == foreground)
        #expect(projection.defaultBackgroundPacked == background)
        #expect(projection.overlay.cursor == GhosttyTerminalCursor(row: 0, col: 5))
    }

    @Test
    func extendedColorTranscriptProjectsPaletteAndTruecolorCells() async throws {
        let runtime = try TerminalVTRuntime(cols: 6, rows: 1, appearance: .defaultDark)

        // 256-color foreground and background, a truecolor foreground,
        // and an aixterm bright foreground - each projected to packed RGB.
        let result = await runtime.write(
            Data("\u{1B}[38;5;196mR\u{1B}[48;5;21mS\u{1B}[0m\u{1B}[38;2;18;52;86mT\u{1B}[m\u{1B}[92mU".utf8)
        )

        let foreground = Self.dark.foreground.packedRGB
        let background = Self.dark.background.packedRGB
        let brightGreen = GhosttyTerminalAppearance.ghosttyDarkPalette[10].packedRGB
        let row = try #require(result.surfaceUpdate.frameProjection.row(at: 0))
        let golden = [
            cell(0, "R", foreground: 0xFF0000, background: background),
            cell(1, "S", foreground: 0xFF0000, background: 0x0000FF),
            cell(2, "T", foreground: 0x123456, background: background),
            cell(3, "U", foreground: brightGreen, background: background),
            cell(4, " ", foreground: foreground, background: background),
            cell(5, " ", foreground: foreground, background: background)
        ]

        #expect(row.cells == golden)
    }

    @Test
    func inverseTranscriptSwapsProjectedCellColors() async throws {
        let runtime = try TerminalVTRuntime(cols: 4, rows: 1, appearance: .defaultDark)

        let result = await runtime.write(Data("\u{1B}[7mX\u{1B}[27mY".utf8))

        let foreground = Self.dark.foreground.packedRGB
        let background = Self.dark.background.packedRGB
        let row = try #require(result.surfaceUpdate.frameProjection.row(at: 0))

        #expect(row.cells[0] == cell(0, "X", foreground: background, background: foreground))
        #expect(row.cells[1] == cell(1, "Y", foreground: foreground, background: background))
    }

    // MARK: - Cursor addressing

    @Test
    func cursorAddressedTranscriptProjectsGoldenScreenLines() async throws {
        let runtime = try TerminalVTRuntime(cols: 8, rows: 3)

        _ = await runtime.write(Data("top\u{1B}[2;3Hmid\u{1B}[3;1Hbot".utf8))

        let lines = await runtime.screenLines()
        #expect(lines.map(\.text) == [
            "top     ",
            "  mid   ",
            "bot     "
        ])
    }

    @Test
    func cursorSaveRestoreAndEraseTranscriptProjectsGoldenScreen() async throws {
        let runtime = try TerminalVTRuntime(cols: 10, rows: 3)

        // Fill three rows, save the cursor (DECSC), overwrite via CUP,
        // restore (DECRC) and append, then erase-to-end-of-line (EL).
        let transcript = "AAAA\r\nBBBB\r\nCCCC\u{1B}7"
            + "\u{1B}[1;1HX\u{1B}[2;3HY\u{1B}8Z"
            + "\u{1B}[1;3H\u{1B}[0K"
        let result = await runtime.write(Data(transcript.utf8))

        let lines = await runtime.screenLines()
        #expect(lines.map(\.text) == [
            "XA        ",
            "BBYB      ",
            "CCCCZ     "
        ])
        #expect(result.surfaceUpdate.surfaceState.cursor == GhosttyTerminalCursor(row: 0, col: 2))
    }

    // MARK: - Alt screen

    @Test
    func altScreenTranscriptEntersPaintsAndRestoresPrimaryScreen() async throws {
        let runtime = try TerminalVTRuntime(cols: 20, rows: 3)

        _ = await runtime.write(Data("primary$ ".utf8))
        let entered = await runtime.write(Data("\u{1B}[?1049h\u{1B}[HALT MODE".utf8))
        let altLines = await runtime.screenLines()
        let exited = await runtime.write(Data("\u{1B}[?1049l".utf8))
        let restoredLines = await runtime.screenLines()

        #expect(entered.surfaceUpdate.surfaceState.altScreenMode == true)
        #expect(altLines.map(\.text) == [
            padded("ALT MODE", cols: 20),
            padded("", cols: 20),
            padded("", cols: 20)
        ])
        #expect(exited.surfaceUpdate.surfaceState.altScreenMode == false)
        // DECSET 1049 restores the primary screen and the saved cursor.
        #expect(restoredLines.map(\.text) == [
            padded("primary$", cols: 20),
            padded("", cols: 20),
            padded("", cols: 20)
        ])
        #expect(exited.surfaceUpdate.surfaceState.cursor == GhosttyTerminalCursor(row: 0, col: 9))
    }

    // MARK: - Scroll regions (DECSTBM)

    @Test
    func scrollRegionTranscriptScrollsOnlyWithinMargins() async throws {
        let runtime = try TerminalVTRuntime(cols: 10, rows: 5)

        _ = await runtime.write(Data("r1\r\nr2\r\nr3\r\nr4\r\nr5".utf8))
        // Restrict scrolling to rows 2-4, move to the region bottom, and
        // line-feed: r2 scrolls out, r3/r4 shift up, r1 and r5 stay.
        _ = await runtime.write(Data("\u{1B}[2;4r".utf8))
        let result = await runtime.write(Data("\u{1B}[4;1H\r\nnew".utf8))

        let lines = await runtime.screenLines()
        #expect(lines.map(\.text) == [
            padded("r1", cols: 10),
            padded("r3", cols: 10),
            padded("r4", cols: 10),
            padded("new", cols: 10),
            padded("r5", cols: 10)
        ])
        #expect(result.surfaceUpdate.surfaceState.cursor == GhosttyTerminalCursor(row: 3, col: 3))
        // Region scrolling discards the scrolled-out row - no scrollback.
        #expect(result.surfaceUpdate.surfaceState.scrollbackRows == 0)
    }

    // MARK: - Wide glyphs and emoji

    @Test
    func wideGlyphTranscriptProjectsCJKAndEmojiCellWidths() async throws {
        let runtime = try TerminalVTRuntime(cols: 12, rows: 2)

        let result = await runtime.write(Data("Aあ\u{1F600}B".utf8))

        let row = try #require(result.surfaceUpdate.frameProjection.row(at: 0))
        #expect(row.cells.prefix(6).map(\.grapheme) == ["A", "あ", "", "\u{1F600}", "", "B"])
        #expect(row.cells.prefix(6).map(\.isWide) == [false, true, false, true, false, false])
        #expect(row.cells.prefix(6).map(\.isWideContinuation) == [false, false, true, false, true, false])
    }

    @Test
    func emojiVariationSelectorAndZWJTranscriptDocumentClusterBoundary() async throws {
        // Engine boundary (libghostty-vt at the pinned commit, default
        // mode-2027 grapheme clustering off): a VS16-selected emoji keeps
        // its base character width - U+2602 U+FE0F stays one narrow cell
        // with the selector preserved in the grapheme - and a ZWJ sequence
        // is not merged into a single cluster: woman+ZWJ and laptop render
        // as two separate wide cells. If a future engine bump flips that
        // default, these assertions are the tripwire that documents it.
        let runtime = try TerminalVTRuntime(cols: 12, rows: 2)

        let result = await runtime.write(
            Data("C\u{2602}\u{FE0F}D\r\nE\u{1F469}\u{200D}\u{1F4BB}F".utf8)
        )

        let projection = result.surfaceUpdate.frameProjection
        let vs16Row = try #require(projection.row(at: 0))
        #expect(vs16Row.cells.prefix(3).map(\.grapheme) == ["C", "\u{2602}\u{FE0F}", "D"])
        #expect(vs16Row.cells.prefix(3).map(\.isWide) == [false, false, false])

        let zwjRow = try #require(projection.row(at: 1))
        #expect(zwjRow.cells.prefix(6).map(\.grapheme) == [
            "E", "\u{1F469}\u{200D}", "", "\u{1F4BB}", "", "F"
        ])
        #expect(zwjRow.cells.prefix(6).map(\.isWide) == [false, true, false, true, false, false])
        #expect(zwjRow.cells.prefix(6).map(\.isWideContinuation) == [false, false, true, false, true, false])
    }

    // MARK: - OSC title reporting

    @Test
    func oscTitleTranscriptReportsTitleForBELAndSTTerminators() async throws {
        let runtime = try TerminalVTRuntime(cols: 20, rows: 2)

        let osc0 = await runtime.write(Data("\u{1B}]0;devys golden\u{07}".utf8))
        let osc2 = await runtime.write(Data("\u{1B}]2;second title\u{1B}\\".utf8))
        let unchanged = await runtime.write(Data("plain output".utf8))

        #expect(osc0.title == "devys golden")
        #expect(osc2.title == "second title")
        #expect(unchanged.title == "second title")
    }

    // MARK: - Full-screen vim session

    @Test
    func vimSessionTranscriptProjectsFullScreenGolden() async throws {
        let bytes = try #require(Data(base64Encoded: Self.vimTranscriptBase64))
        #expect(bytes.count == 2634)
        let runtime = try TerminalVTRuntime(cols: 80, rows: 24)
        _ = await runtime.write(Data("before-vim$ ".utf8))

        // Steady state: vim -u NONE editing golden.txt with two typed
        // lines, ":set number", laststatus=2, cursor parked at gg0.
        let steady = await runtime.write(Data(bytes.prefix(Self.vimSteadyStateByteCount)))

        #expect(steady.surfaceUpdate.surfaceState.altScreenMode == true)
        #expect(steady.surfaceUpdate.surfaceState.cursorVisible == true)
        // gg0: first text column, past the 8-column number gutter.
        #expect(steady.surfaceUpdate.surfaceState.cursor == GhosttyTerminalCursor(row: 0, col: 8))

        var golden = [
            padded("      1 Hello from Devys terminal.", cols: 80),
            padded("      2 Golden transcript line two.", cols: 80)
        ]
        golden += Array(repeating: padded("~", cols: 80), count: 20)
        golden.append(padded("golden.txt [+]", cols: 80))
        golden.append(padded(":set number", cols: 80))
        let steadyLines = await runtime.screenLines()
        #expect(steadyLines.map(\.text) == golden)

        // The number gutter is painted with SGR 38;5;130 (xterm 130).
        let firstRow = try #require(steady.surfaceUpdate.frameProjection.row(at: 0))
        #expect(firstRow.cells[0].foregroundPacked == 0xAF5F00)

        // ":q!" leaves the alt screen and restores the primary screen
        // and cursor exactly where the shell prompt left them.
        let exitTail = Data(bytes.suffix(bytes.count - Self.vimSteadyStateByteCount))
        let exited = await runtime.write(exitTail)

        #expect(exited.surfaceUpdate.surfaceState.altScreenMode == false)
        #expect(exited.surfaceUpdate.surfaceState.cursorVisible == true)
        #expect(exited.surfaceUpdate.surfaceState.cursor == GhosttyTerminalCursor(row: 0, col: 12))
        let restoredLines = await runtime.screenLines()
        #expect(restoredLines.first?.text == padded("before-vim$", cols: 80))
        #expect(restoredLines.dropFirst().allSatisfy { $0.text == padded("", cols: 80) })
    }

    // MARK: - Fixture

    /// A real `vim -u NONE -n golden.txt` byte transcript captured through
    /// a PTY at 80x24 (TERM=xterm-256color, vim 9.1 on macOS): status line
    /// via ":set laststatus=2", two typed lines in insert mode,
    /// ":set number", "gg0", then ":q!". Frozen bytes - the test replays
    /// them through the engine and never invokes vim.
    static let vimTranscriptBase64 = ""
        + "G1s/MTA0OWgbWz40OzJtG1s/MWgbPRtbPzIwMDRoG1sxOzI0chtbPzEyaBtbPzEybBtbMjI7MnQb"
        + "WzIyOzF0G1syN20bWzIzbRtbMjltG1ttG1tIG1syShtbPzI1bBtbMjQ7MUgiZ29sZGVuLnR4dCIg"
        + "W05ldyBGaWxlXRtbMjsxSBtbOTRtfiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAbWzM7MUh+ICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgIBtbNDsxSH4gICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgG1s1OzFIfiAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAbWzY7MUh+ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIBtbNzsxSH4gICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgG1s4OzFIfiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAbWzk7MUh+ICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgIBtbMTA7MUh+ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIBtbMTE7MUh+"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgIBtbMTI7MUh+ICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIBtbMTM7"
        + "MUh+ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgIBtbMTQ7MUh+ICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIBtb"
        + "MTU7MUh+ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgIBtbMTY7MUh+ICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "IBtbMTc7MUh+ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIBtbMTg7MUh+ICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgIBtbMTk7MUh+ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIBtbMjA7MUh+ICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgIBtbMjE7MUh+ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIBtbMjI7MUh+ICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgIBtbMjM7MUh+ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIBtbMTsxSBtbPzI1aBtbPzRt"
        + "G1s/MjVsG1ttG1syNDsxSBtbSxtbMjQ7MUg6c2V0IGxhc3RzdGF0dXM9Mg0bWzIzOzFIG1sxbRtb"
        + "N21nb2xkZW4udHh0ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAg"
        + "ICAgICAgICAgICAgICAgICAgICAgICAgIBtbMTsxSBtbPzI1aBtbPzIwMDRsG1s+NDttG1s/MjVs"
        + "G1ttSGVsbG8gZnJvbSBEZXZ5cyB0ZXJtaW5hbC4bWzIzOzEySBtbMW0bWzdtWytdG1sxOzI3SBtb"
        + "PzI1aBtbPzI1bBtbbRtbMjsxSBtbSxtbMjsxSBtbPzI1aBtbPzI1bEdvbGRlbiB0cmFuc2NyaXB0"
        + "IGxpbmUgdHdvLhtbPzI1aBtbPzIwMDRoG1s+NDsybQgbWz80bRtbPzI1bBtbMjQ7MUgbW0sbWzI0"
        + "OzFIOnNldCBudW1iZXING1sxOzFIG1szODs1OzEzMG0gICAgICAxIBtbbUhlbGxvIGZyb20gRGV2"
        + "eXMgdGVybWluYWwuDQobWzM4OzU7MTMwbSAgICAgIDIgG1ttR29sZGVuIHRyYW5zY3JpcHQgbGlu"
        + "ZSB0d28uCBtbPzI1aBtbMTs5SBtbPzI1bBtbMjQ7MUgbW0sbWzI0OzFIOnEhDRtbPzIwMDRsG1s+"
        + "NDttG1syMzsydBtbMjM7MXQbWzI0OzFIG1tLG1syNDsxSBtbPzIwMDRsG1s/MWwbPhtbPzEwNDls"
        + "G1s/MjVoG1s+NDtt"

    /// Byte offset separating the in-session steady state from the ":q!"
    /// exit tail, recorded at capture time.
    static let vimSteadyStateByteCount = 2527
}

private func cell(
    _ column: Int,
    _ grapheme: String,
    foreground: UInt32,
    background: UInt32,
    isBold: Bool = false,
    isWide: Bool = false
) -> GhosttyTerminalProjectedCell {
    GhosttyTerminalProjectedCell(
        column: column,
        grapheme: grapheme,
        foregroundPacked: foreground,
        backgroundPacked: background,
        isBold: isBold,
        isWide: isWide
    )
}

private func continuationCell(
    _ column: Int,
    foreground: UInt32,
    background: UInt32
) -> GhosttyTerminalProjectedCell {
    GhosttyTerminalProjectedCell(
        column: column,
        grapheme: "",
        foregroundPacked: foreground,
        backgroundPacked: background,
        isWideContinuation: true
    )
}
