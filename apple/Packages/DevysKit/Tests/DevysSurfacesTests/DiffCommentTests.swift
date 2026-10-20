import DevysSurfaces
import Testing

/// Review comments read the same from the native apps as from the web diff surface.
@Suite struct DiffCommentTests {
    let patch = """
    diff --git a/money.ts b/money.ts
    index 1111111..2222222 100644
    --- a/money.ts
    +++ b/money.ts
    @@ -1,3 +1,3 @@
    -const share = Math.round(total / people);
    +const share = Math.floor(total / people);
     export { share };
     export default share;
    @@ -10,2 +10,3 @@ function split() {
     const rest = total - share * people;
    +log(rest);
     return rest;
    diff --git a/notes.md b/notes.md
    --- a/notes.md
    +++ b/notes.md
    @@ -1 +1 @@
    -Old
    +New
    \\ No newline at end of file
    """

    @Test func hunkTextIsTheHunkHoldingTheFirstSelectedLine() {
        let second = DiffComment.hunkText(patch, DiffSelection(path: "money.ts", side: "additions", start: 11, end: 12))
        #expect(second == "@@ -10,2 +10,3 @@ function split() {\n const rest = total - share * people;\n+log(rest);\n return rest;")
        let old = DiffComment.hunkText(patch, DiffSelection(path: "money.ts", side: "deletions", start: 1, end: 1))
        #expect(old.hasPrefix("@@ -1,3 +1,3 @@") && old.hasSuffix(" export default share;"))
        let trailer = DiffComment.hunkText(patch, DiffSelection(path: "notes.md", side: "additions", start: 1, end: 1))
        #expect(trailer == "@@ -1 +1 @@\n-Old\n+New\n\\ No newline at end of file")
        #expect(DiffComment.hunkText(patch, DiffSelection(path: "other.ts", side: "additions", start: 1, end: 1)).isEmpty)
    }

    @Test func hunkHashIsTheFirstEightHexOfSHA256() {
        // SHA-256("abc") = ba7816bf…
        #expect(DiffComment.hunkHash("abc") == "ba7816bf")
        #expect(DiffComment.hunkHash("") == "e3b0c442")
    }

    @Test func lineNamesPathLinesSideBaseAndHunk() {
        let range = DiffComment(path: "money.ts", side: "additions", start: 3, end: 5, hunk: "ba7816bf", base: "0123456789abcdef", text: "Use floor here")
        #expect(range.line == "money.ts lines 3–5 (new, base 01234567, hunk ba7816bf): Use floor here")
        let single = DiffComment(path: "money.ts", side: "deletions", start: 1, end: 1, hunk: "e3b0c442", text: "Why remove this?")
        #expect(single.line == "money.ts line 1 (old, hunk e3b0c442): Why remove this?")
        #expect(DiffComment.review("Fix rounding", [range, single]) == """
        Review comments on Fix rounding:
        money.ts lines 3–5 (new, base 01234567, hunk ba7816bf): Use floor here
        money.ts line 1 (old, hunk e3b0c442): Why remove this?
        """)
    }

    @Test func commentHashesItsHunkFromThePatch() {
        let selection = DiffSelection(path: "money.ts", side: "additions", start: 11, end: 11)
        let comment = DiffComment(selection, in: patch, base: nil, text: "Drop the log")
        #expect(comment.hunk == DiffComment.hunkHash(DiffComment.hunkText(patch, selection)))
        #expect(comment.line.hasPrefix("money.ts line 11 (new, hunk "))
    }
}
