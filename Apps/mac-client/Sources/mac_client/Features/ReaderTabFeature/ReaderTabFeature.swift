import ComposableArchitecture
import Foundation

enum MarkdownReaderRouting {
    static let supportedExtensions: Set<String> = ["md", "mdx", "markdown", "txt"]

    static func isReadable(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

enum ReaderMode: Hashable, Sendable {
    case read
    case edit
}

@Reducer
struct ReaderTabFeature {
    @ObservableState
    struct State: Equatable {
        var fileURL: URL
        var projectRootURL: URL?
        var relativePath: String
        var mode: ReaderMode = .read
        var blocks: [MarkdownBlock] = []
        var isDirty = false

        init(fileURL: URL, projectRootURL: URL? = nil) {
            let standardizedFileURL = fileURL.standardizedFileURL
            let standardizedProjectRootURL = projectRootURL?.standardizedFileURL
            self.fileURL = standardizedFileURL
            self.projectRootURL = standardizedProjectRootURL
            self.relativePath = Self.makeRelativePath(
                fileURL: standardizedFileURL,
                projectRootURL: standardizedProjectRootURL
            )
        }

        private static func makeRelativePath(fileURL: URL, projectRootURL: URL?) -> String {
            guard let projectRootURL else { return fileURL.path }
            let rootPath = projectRootURL.standardizedFileURL.path
            let filePath = fileURL.standardizedFileURL.path
            guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else {
                return filePath
            }
            return String(filePath.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
    }

    enum Action: Equatable {
        case modeChanged(ReaderMode)
        case toggleMode
        case documentContentChanged(String)
        case dirtyStateChanged(Bool)
        case revealInFinderRequested
        case revealInFinderFinished
    }

    @Dependency(\.documentClient) private var documentClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .modeChanged(mode):
                state.mode = mode
                return .none

            case .toggleMode:
                state.mode = state.mode == .read ? .edit : .read
                return .none

            case let .documentContentChanged(content):
                state.blocks = MarkdownDocumentParser.parse(content)
                return .none

            case let .dirtyStateChanged(isDirty):
                state.isDirty = isDirty
                return .none

            case .revealInFinderRequested:
                let fileURL = state.fileURL
                return .run { send in
                    await documentClient.revealInFinder(fileURL)
                    await send(.revealInFinderFinished)
                }

            case .revealInFinderFinished:
                return .none
            }
        }
    }
}
