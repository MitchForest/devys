public import SwiftUI
public import WebKit

/// What a document surface shows. The web side renders it (`src/surfaces`); native code fetches
/// it and keeps the session token, so the page never makes a request of its own.
public enum SurfaceContent: Equatable, Sendable {
    case diff(patch: String, comments: [DiffComment])
    /// A markdown document; `version` changes when its text is replaced from outside. A deck
    /// (`*.slides.md` or `marp: true`) edits beside its slides, and the page says `deck`.
    /// `readOnly` shows it without editing.
    case markdown(String, name: String, version: String, readOnly: Bool)
    case code(name: String, contents: String)
    /// A spreadsheet file (xlsx, xls or CSV), edited in place unless `readOnly`.
    case sheet(Data, name: String, version: String, readOnly: Bool)
    /// An Excalidraw drawing as its JSON, edited in place unless `readOnly`.
    case whiteboard(String, version: String, readOnly: Bool)
}

/// An edited file as the page writes it: text, or bytes.
public enum SurfaceFile: Equatable, Sendable {
    case text(String)
    case bytes(Data)
}

/// Asks the page shown in a `SurfaceView` for what it holds: the edited file on Save, a deck's
/// PowerPoint copy on Export.
@MainActor
public final class SurfaceHandle {
    weak var bridge: SurfaceBridge?

    public init() {}

    public func serialize() async -> SurfaceFile? {
        guard let value = try? await bridge?.call("return window.devysSurface.serialize()") as? [String: Any] else { return nil }
        if let text = value["text"] as? String { return .text(text) }
        return (value["base64"] as? String).flatMap { Data(base64Encoded: $0) }.map(SurfaceFile.bytes)
    }

    public func exportDeck() async -> Data? {
        (try? await bridge?.call("return await window.devysSurface.exportDeck()") as? String).flatMap { Data(base64Encoded: $0) }
    }
}

/// Text the reader selected in a document, and where it sits in the markdown (-1 if hidden).
public struct TextSelection: Equatable, Sendable, Decodable {
    public let start: Int
    public let end: Int
    public let quote: String
}

/// Lines the reader selected in a diff, to comment on.
public struct DiffSelection: Equatable, Sendable, Decodable {
    public let path: String
    public let side: String
    public let start: Int
    public let end: Int

    public init(path: String, side: String, start: Int, end: Int) {
        self.path = path
        self.side = side
        self.start = start
        self.end = end
    }
}

/// The bundled web surfaces in a web view (.docs/COMPONENTS.md#surfaces): loaded offline from the
/// app through the `devys-surface` scheme, one shared configuration so later surfaces open fast.
public struct SurfaceView {
    let content: SurfaceContent
    let onSelect: (DiffSelection?) -> Void
    let onRendered: (_ files: Int) -> Void
    let onChange: (String) -> Void
    let onSelectText: (TextSelection?) -> Void
    let onEdited: () -> Void
    let onDeck: () -> Void
    let handle: SurfaceHandle?
    @Environment(\.colorScheme) private var colorScheme

    public init(
        _ content: SurfaceContent,
        onSelect: @escaping (DiffSelection?) -> Void = { _ in },
        onRendered: @escaping (_ files: Int) -> Void = { _ in },
        onChange: @escaping (String) -> Void = { _ in },
        onSelectText: @escaping (TextSelection?) -> Void = { _ in },
        onEdited: @escaping () -> Void = {},
        onDeck: @escaping () -> Void = {},
        handle: SurfaceHandle? = nil
    ) {
        self.content = content
        self.onSelect = onSelect
        self.onRendered = onRendered
        self.onChange = onChange
        self.onSelectText = onSelectText
        self.onEdited = onEdited
        self.onDeck = onDeck
        self.handle = handle
    }

    public func makeCoordinator() -> SurfaceBridge { SurfaceBridge() }

    fileprivate func makeWebView(_ bridge: SurfaceBridge) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(SurfaceFiles(), forURLScheme: SurfaceFiles.scheme)
        configuration.userContentController.add(bridge, name: "devys")
        let view = WKWebView(frame: .zero, configuration: configuration)
        #if os(macOS)
        view.setValue(false, forKey: "drawsBackground")
        #else
        view.isOpaque = false
        view.backgroundColor = .clear
        #endif
        bridge.view = view
        view.load(URLRequest(url: URL(string: "\(SurfaceFiles.scheme)://bundle/surfaces.html")!))
        return view
    }

    fileprivate func update(_ bridge: SurfaceBridge) {
        bridge.onSelect = onSelect
        bridge.onRendered = onRendered
        bridge.onChange = onChange
        bridge.onSelectText = onSelectText
        bridge.onEdited = onEdited
        bridge.onDeck = onDeck
        handle?.bridge = bridge
        bridge.show(content, dark: colorScheme == .dark)
    }
}

#if os(macOS)
extension SurfaceView: NSViewRepresentable {
    public func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    public func updateNSView(_ view: WKWebView, context: Context) { update(context.coordinator) }
}
#else
extension SurfaceView: UIViewRepresentable {
    public func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    public func updateUIView(_ view: WKWebView, context: Context) { update(context.coordinator) }
}
#endif

/// Carries content into the page once it says it is ready, and selections back out.
public final class SurfaceBridge: NSObject, WKScriptMessageHandler {
    weak var view: WKWebView?
    var onSelect: (DiffSelection?) -> Void = { _ in }
    var onRendered: (Int) -> Void = { _ in }
    var onChange: (String) -> Void = { _ in }
    var onSelectText: (TextSelection?) -> Void = { _ in }
    var onEdited: () -> Void = {}
    var onDeck: () -> Void = {}
    private var ready = false
    private var pending: (SurfaceContent, Bool)?
    private var shown: (SurfaceContent, Bool)?

    func show(_ content: SurfaceContent, dark: Bool) {
        if let shown, shown.0 == content, shown.1 == dark { return }
        pending = (content, dark)
        flush()
    }

    private func flush() {
        guard ready, let (content, dark) = pending, let view else { return }
        pending = nil
        shown = (content, dark)
        let payload: [String: Any] = switch content {
        case .diff(let patch, let comments):
            [
                "kind": "diff", "patch": patch, "dark": dark,
                "comments": comments.map { ["path": $0.path, "side": $0.side, "start": $0.start, "end": $0.end, "text": $0.text] }
            ]
        case .markdown(let markdown, let name, let version, let readOnly):
            ["kind": "markdown", "name": name, "markdown": markdown, "version": version, "readOnly": readOnly, "dark": dark]
        case .code(let name, let contents): ["kind": "code", "name": name, "contents": contents, "dark": dark]
        case .sheet(let data, let name, let version, let readOnly):
            ["kind": "sheet", "name": name, "base64": data.base64EncodedString(), "version": version, "readOnly": readOnly, "dark": dark]
        case .whiteboard(let json, let version, let readOnly): ["kind": "whiteboard", "json": json, "version": version, "readOnly": readOnly, "dark": dark]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(bytes: data, encoding: .utf8) else { return }
        view.evaluateJavaScript("window.devysSurface.show(\(json))")
    }

    /// Runs script in the page and returns its result (a promise is awaited).
    @MainActor
    func call(_ body: String) async throws -> Any? {
        guard let view else { return nil }
        return try await view.callAsyncJavaScript(body, contentWorld: .page)
    }

    public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            flush()
        case "select":
            let selection = (body["selection"] as? [String: Any]).flatMap { value in
                (try? JSONSerialization.data(withJSONObject: value)).flatMap { try? JSONDecoder().decode(DiffSelection.self, from: $0) }
            }
            onSelect(selection)
        case "rendered":
            onRendered(body["files"] as? Int ?? 0)
        case "change":
            if let markdown = body["markdown"] as? String { onChange(markdown) }
        case "edited":
            onEdited()
        case "deck":
            onDeck()
        case "selectText":
            let selection = (body["selection"] as? [String: Any]).flatMap { value in
                (try? JSONSerialization.data(withJSONObject: value)).flatMap { try? JSONDecoder().decode(TextSelection.self, from: $0) }
            }
            onSelectText(selection)
        default:
            break
        }
    }
}

/// Serves the bundled surfaces from the app, never from the network.
final class SurfaceFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "devys-surface"
    private static let root = Bundle.module.url(forResource: "surfaces", withExtension: nil)

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let root = Self.root else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let relative = url.path.split(separator: "/").filter { $0 != ".." && $0 != "." }.joined(separator: "/")
        let file = root.appending(path: relative)
        guard file.path.hasPrefix(root.path), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let types = ["html": "text/html", "js": "text/javascript", "css": "text/css", "wasm": "application/wasm", "json": "application/json", "woff2": "font/woff2"]
        let type = types[file.pathExtension] ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: "utf-8"))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
