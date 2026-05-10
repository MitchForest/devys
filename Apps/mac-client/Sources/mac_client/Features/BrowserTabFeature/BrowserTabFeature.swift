import ComposableArchitecture
import Foundation

@Reducer
struct BrowserTabFeature {
    @ObservableState
    struct State: Equatable {
        var url: URL
        var projectRootURL: URL?
        var fileReadAccessURL: URL?
        var title: String

        init(url: URL, projectRootURL: URL? = nil, fileReadAccessURL: URL? = nil) {
            let standardizedURL = url.standardizedForBrowserTab
            self.url = standardizedURL
            self.projectRootURL = projectRootURL?.standardizedFileURL
            self.fileReadAccessURL = fileReadAccessURL?.standardizedFileURL
            self.title = BrowserTabRouting.displayTitle(for: standardizedURL, title: nil)
        }

        var displayTitle: String {
            BrowserTabRouting.displayTitle(for: url, title: title)
        }
    }

    enum Action: Equatable {
        case metadataChanged(BrowserTabMetadata)
        case titlePublished
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .metadataChanged(metadata):
                state.url = metadata.url.standardizedForBrowserTab
                state.title = metadata.title
                return .none

            case .titlePublished:
                return .none
            }
        }
    }
}

struct BrowserTabMetadata: Equatable, Sendable {
    var url: URL
    var title: String

    init(url: URL, title: String) {
        self.url = url.standardizedForBrowserTab
        self.title = title
    }
}

enum BrowserTabRouting {
    static let previewExtensions: Set<String> = ["html", "htm", "xhtml"]

    static func isBrowserPreviewFile(_ url: URL) -> Bool {
        previewExtensions.contains(url.pathExtension.lowercased())
    }

    static func readAccessURL(for fileURL: URL, projectRootURL: URL?) -> URL {
        let fileURL = fileURL.standardizedFileURL
        if let projectRootURL = projectRootURL?.standardizedFileURL,
           fileURL.isDescendant(of: projectRootURL) {
            return projectRootURL
        }
        return fileURL.deletingLastPathComponent().standardizedFileURL
    }

    static func normalizedUserURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL
        }

        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("localhost")
            || lowercased.hasPrefix("127.0.0.1")
            || lowercased.hasPrefix("[::1]") {
            return URL(string: "http://\(trimmed)")
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return url.standardizedForBrowserTab
        }

        return URL(string: "https://\(trimmed)")
    }

    static func localhostURL(port: Int) -> URL? {
        URL(string: "http://localhost:\(port)")
    }

    static func displayTitle(for url: URL, title: String?) -> String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        if url.isFileURL {
            let name = url.lastPathComponent
            return name.isEmpty ? url.path : name
        }
        return url.host(percentEncoded: false) ?? url.absoluteString
    }
}

extension URL {
    var standardizedForBrowserTab: URL {
        isFileURL ? standardizedFileURL : self
    }

    fileprivate func isDescendant(of parent: URL) -> Bool {
        let path = standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return path == parentPath || path.hasPrefix(parentPath + "/")
    }
}
