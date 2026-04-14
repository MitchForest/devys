import Foundation
import Testing
import Editor
import Workspace
@testable import mac_client

@Suite("Ripgrep Text Search Service Tests")
struct RipgrepTextSearchServiceTests {
    @Test("Parses match events and converts UTF-8 offsets into character columns")
    func parseMatchesConvertsUTF8OffsetsToCharacterColumns() throws {
        let payload = [
            #"{"type":"begin","data":{"path":{"text":"Sources/Example.swift"}}}"#,
            [
                #"{"type":"match","data":{"path":{"text":"Sources/Example.swift"},"#,
                #""lines":{"text":"héllo world\n"},"line_number":3,"absolute_offset":0,"#,
                #""submatches":[{"match":{"text":"world"},"start":7,"end":12}]}}"#,
            ].joined(),
            [
                #"{"type":"summary","data":{"elapsed_total":{"human":"0.001s","nanos":1,"secs":0},"#,
                #""stats":{"bytes_printed":0,"bytes_searched":11,"elapsed":{"human":"0.000s","nanos":1,"secs":0},"#,
                #""matched_lines":1,"matches":1,"searches":1,"searches_with_match":1}}}"#,
            ].joined(),
        ].joined(separator: "\n")

        let matches = try RipgrepTextSearchService.parseMatches(
            from: Data(payload.utf8),
            workspaceID: "workspace-1",
            rootURL: URL(fileURLWithPath: "/tmp/search-root")
        )

        #expect(matches.count == 1)

        let match = try #require(matches.first)
        #expect(match.relativePath == "Sources/Example.swift")
        #expect(match.lineNumber == 3)
        #expect(match.columnNumber == 7)
        #expect(match.preview == "héllo world")
        #expect(match.match == EditorSearchMatch(
            startLine: 2,
            startColumn: 6,
            endLine: 2,
            endColumn: 11
        ))
    }

    @Test("Parses multiple match records and ignores non-match events")
    func parseMatchesIgnoresNonMatchEvents() throws {
        let payload = [
            #"{"type":"begin","data":{"path":{"text":"One.swift"}}}"#,
            [
                #"{"type":"match","data":{"path":{"text":"One.swift"},"#,
                #""lines":{"text":"let first = true\n"},"line_number":1,"absolute_offset":0,"#,
                #""submatches":[{"match":{"text":"first"},"start":4,"end":9}]}}"#,
            ].joined(),
            [
                #"{"type":"end","data":{"path":{"text":"One.swift"},"binary_offset":null,"#,
                #""stats":{"elapsed":{"secs":0,"nanos":1,"human":"0.001s"},"searches":1,"searches_with_match":1,"#,
                #""bytes_searched":16,"bytes_printed":0,"matched_lines":1,"matches":1}}}"#,
            ].joined(),
            [
                #"{"type":"match","data":{"path":{"text":"Two.swift"},"#,
                #""lines":{"text":"let second = true\n"},"line_number":4,"absolute_offset":0,"#,
                #""submatches":[{"match":{"text":"second"},"start":4,"end":10}]}}"#,
            ].joined(),
        ].joined(separator: "\n")

        let matches = try RipgrepTextSearchService.parseMatches(
            from: Data(payload.utf8),
            workspaceID: "workspace-2",
            rootURL: URL(fileURLWithPath: "/tmp/search-root")
        )

        #expect(matches.map(\.relativePath) == ["One.swift", "Two.swift"])
        #expect(matches.map(\.lineNumber) == [1, 4])
    }
}
