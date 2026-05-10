import ComposableArchitecture
import Editor
import Foundation

@Reducer
struct FileTabFeature {
    @ObservableState
    struct State: Equatable {
        var fileURL: URL
        var projectRootURL: URL?
        var relativePath: String
        var previewRequest: DocumentPreviewRequest
        var phase: FileTabPhase = .idle
        var isDirty = false
        var isSaving = false
        var saveErrorMessage: String?

        init(
            fileURL: URL,
            projectRootURL: URL? = nil,
            previewRequest: DocumentPreviewRequest = DocumentPreviewRequest(maxBytes: 1_500_000)
        ) {
            let standardizedFileURL = fileURL.standardizedFileURL
            let standardizedProjectRootURL = projectRootURL?.standardizedFileURL
            self.fileURL = standardizedFileURL
            self.projectRootURL = standardizedProjectRootURL
            self.relativePath = Self.makeRelativePath(
                fileURL: standardizedFileURL,
                projectRootURL: standardizedProjectRootURL
            )
            self.previewRequest = previewRequest
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
        case task
        case previewLoaded(LoadedDocumentPreview)
        case previewFailed(String)
        case editorLoaded
        case dirtyStateChanged(Bool)
        case saveRequested(content: String, saveURL: URL?)
        case saveSucceeded(URL)
        case saveFailed(String)
        case revealInFinderRequested
        case revealInFinderFinished
    }

    @Dependency(\.documentClient) private var documentClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                state.phase = .loading
                state.saveErrorMessage = nil
                let fileURL = state.fileURL
                let request = state.previewRequest
                return .run { send in
                    do {
                        let preview = try await documentClient.loadPreview(fileURL, request)
                        await send(.previewLoaded(preview))
                    } catch {
                        await send(.previewFailed(error.localizedDescription))
                    }
                }

            case let .previewLoaded(preview):
                state.phase = .preview(preview)
                return .none

            case let .previewFailed(message):
                state.phase = .failed(message)
                return .none

            case .editorLoaded:
                state.phase = .loaded
                return .none

            case let .dirtyStateChanged(isDirty):
                state.isDirty = isDirty
                return .none

            case let .saveRequested(content, saveURL):
                let destinationURL = (saveURL ?? state.fileURL).standardizedFileURL
                state.isSaving = true
                state.saveErrorMessage = nil
                return .run { send in
                    do {
                        try await documentClient.save(content, destinationURL)
                        await send(.saveSucceeded(destinationURL))
                    } catch {
                        await send(.saveFailed(error.localizedDescription))
                    }
                }

            case .saveSucceeded:
                state.isSaving = false
                state.isDirty = false
                state.saveErrorMessage = nil
                return .none

            case let .saveFailed(message):
                state.isSaving = false
                state.saveErrorMessage = message
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

enum FileTabPhase: Equatable {
    case idle
    case loading
    case preview(LoadedDocumentPreview)
    case loaded
    case failed(String)
}
