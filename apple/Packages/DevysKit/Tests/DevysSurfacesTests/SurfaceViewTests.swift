#if os(macOS)
import AppKit
import DevysSurfaces
import SwiftUI
import Testing

/// Web views in windows, one test at a time.
@MainActor @Suite(.serialized) struct SurfaceViewTests {
/// The bundled web surface loads offline in a real web view and renders a patch.
@Test func diffSurfaceRendersABundledPatch() async throws {
    let patch = """
    diff --git a/money.ts b/money.ts
    --- a/money.ts
    +++ b/money.ts
    @@ -1,2 +1,2 @@
    -const share = Math.round(total / people);
    +const share = Math.floor(total / people);
     export { share };
    """
    var rendered: Int?
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: SurfaceView(.diff(patch: patch, comments: []), onRendered: { rendered = $0 }))
    window.orderFront(nil)
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while rendered == nil, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(100))
    }
    window.close()
    #expect(rendered == 1)
}

/// A markdown document renders in the same bundle.
@Test func markdownSurfaceRenders() async throws {
    var rendered: Int?
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: SurfaceView(.markdown("# Plan\n\nShip it.", name: "plan.md", version: "1", readOnly: false), onRendered: { rendered = $0 }))
    window.orderFront(nil)
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while rendered == nil, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(100))
    }
    window.close()
    #expect(rendered != nil)
}

/// A markdown deck says so, and native code gets its PowerPoint copy through the handle.
@Test func deckExportsThroughTheHandle() async throws {
    var deck = false
    let handle = SurfaceHandle()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let markdown = "---\nmarp: true\n---\n\n# Launch\n\n---\n\n## Plan\n\n- Ship it\n"
    window.contentView = NSHostingView(rootView: SurfaceView(.markdown(markdown, name: "launch.md", version: "1", readOnly: false), onDeck: { deck = true }, handle: handle))
    window.orderFront(nil)
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while !deck, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(100))
    }
    let pptx = await handle.exportDeck()
    let unedited = await handle.serialize()
    window.close()
    #expect(deck)
    #expect(pptx?.prefix(2) == Data("PK".utf8))
    #expect(unedited == nil)
}
}
#endif
