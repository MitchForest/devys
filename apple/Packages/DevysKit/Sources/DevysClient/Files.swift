public import Dependencies
public import CoreGraphics
public import Foundation

/// One entry of a folder in the business's files on the Mac.
public struct FileEntry: Equatable, Sendable, Decodable, Identifiable, Hashable {
    public enum Kind: String, Sendable, WireEnum { case file, directory, repository, other, unknown }
    public let name: String
    public let path: String
    public let kind: Kind
    public let size: Int
    public var id: String { path }

    public init(name: String, path: String, kind: Kind, size: Int = 0) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
    }
}

/// A text file and the revision it was read at.
public struct FileText: Equatable, Sendable, Decodable {
    public let path: String
    public let content: String
    public let revision: String

    public init(path: String, content: String, revision: String) {
        self.path = path
        self.content = content
        self.revision = revision
    }
}

/// A file's bytes and the revision they were read at.
public struct FileBytes: Equatable, Sendable {
    public let data: Data
    public let revision: String

    public init(data: Data, revision: String) {
        self.data = data
        self.revision = revision
    }
}

/// What a save checks first: the revision that was read, that the file is new, or nothing (only
/// derived copies such as a deck's .pptx overwrite without a check).
public enum FileExpectation: Equatable, Sendable {
    case revision(String)
    case new
    case overwrite
}

/// How a save went: saved at a new revision, or the file had changed (with its newer text).
public enum FileSave: Equatable, Sendable {
    case saved(revision: String)
    case conflict(FileText?)
}

/// A comment's anchor: a text range of a document or regions of a PDF page.
public enum FileAnchor: Equatable, Sendable, Encodable {
    case text(start: Int, end: Int, quote: String)
    case pdf(page: Int, rects: [CGRect])

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .text(let start, let end, let quote):
            try container.encode("text", forKey: .kind)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
            try container.encode(quote, forKey: .quote)
        case .pdf(let page, let rects):
            try container.encode("pdf", forKey: .kind)
            try container.encode(page, forKey: .page)
            try container.encode(rects.map { ["x": $0.minX, "y": $0.minY, "width": $0.width, "height": $0.height] }, forKey: .rects)
        }
    }

    private enum Key: String, CodingKey { case kind, start, end, quote, page, rects }
}

public struct FileComment: Equatable, Sendable, Encodable {
    public let anchor: FileAnchor
    public let text: String

    public init(anchor: FileAnchor, text: String) {
        self.anchor = anchor
        self.text = text
    }
}

extension DevysHTTPClient {
    public func files(_ session: DeviceSession, businessID: String, path: String?) async throws -> (root: String, entries: [FileEntry]) {
        struct Page: Decodable { let root: String; let entries: [FileEntry] }
        let query = path.map { "?path=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" } ?? ""
        let page: Page = try await send(authorized(session, path: "api/businesses/\(businessID)/files\(query)"))
        return (page.root, page.entries)
    }

    private func fileQuery(_ path: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    public func fileText(_ session: DeviceSession, businessID: String, path: String) async throws -> FileText {
        try await send(try authorizedQuery(session, "api/businesses/\(businessID)/files/text", path: path))
    }

    public func fileBytes(_ session: DeviceSession, businessID: String, path: String) async throws -> FileBytes {
        let (data, response) = try await response(try authorizedQuery(session, "api/businesses/\(businessID)/files/raw", path: path))
        return FileBytes(data: data, revision: response.value(forHTTPHeaderField: "x-devys-revision") ?? "")
    }

    public func saveFileBytes(_ session: DeviceSession, businessID: String, path: String, data: Data, expected: FileExpectation) async throws -> FileSave {
        struct Saved: Decodable { let revision: String }
        var request = try authorizedQuery(session, "api/businesses/\(businessID)/files/raw", path: path, method: "PUT")
        switch expected {
        case .revision(let revision): request.url = request.url.map { $0.appending(queryItems: [URLQueryItem(name: "expected_revision", value: revision)]) }
        case .new: request.url = request.url.map { $0.appending(queryItems: [URLQueryItem(name: "expected_revision", value: "none")]) }
        case .overwrite: break
        }
        request.httpBody = data
        do {
            let saved: Saved = try await send(request)
            return .saved(revision: saved.revision)
        } catch DevysHTTPError.rejected(409, _) {
            return .conflict(nil)
        }
    }

    public func saveFile(_ session: DeviceSession, businessID: String, path: String, content: String, expectedRevision: String?) async throws -> FileSave {
        struct Body: Encodable {
            let path: String
            let content: String
            let expectedRevision: String?
            enum CodingKeys: String, CodingKey {
                case path, content
                case expectedRevision = "expected_revision"
            }
        }
        struct Saved: Decodable { let revision: String }
        struct Conflict: Decodable { let current: FileText? }
        do {
            let saved: Saved = try await send(json(session, path: "api/businesses/\(businessID)/files/text", method: "PUT", body: Body(path: path, content: content, expectedRevision: expectedRevision)))
            return .saved(revision: saved.revision)
        } catch DevysHTTPError.rejected(409, let message) {
            let conflict = try? Wire.decoder().decode(Conflict.self, from: Data(message.utf8))
            return .conflict(conflict?.current)
        }
    }

    /// Sends comments to an employee's DM, or to a work item's thread when `to` is `work:<id>`.
    public func commentOnFile(_ session: DeviceSession, businessID: String, path: String, employee recipient: String, comments: [FileComment]) async throws {
        struct Body: Encodable { let id: String; let path: String; let employee: String?; let work: String?; let comments: [FileComment] }
        let work = recipient.hasPrefix("work:") ? String(recipient.dropFirst("work:".count)) : nil
        let body = Body(id: UUID().uuidString, path: path, employee: work == nil ? recipient : nil, work: work, comments: comments)
        _ = try await raw(json(session, path: "api/businesses/\(businessID)/files/comments", method: "POST", body: body))
    }

    private func authorizedQuery(_ session: DeviceSession, _ base: String, path: String, method: String = "GET") throws -> URLRequest {
        var request = authorized(session, path: base, method: method)
        guard let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DevysHTTPError.invalidResponse
        }
        components.percentEncodedQuery = "path=\(fileQuery(path))"
        request.url = components.url
        return request
    }
}

/// The business's files on the owner's Mac: folders, text at a revision, bytes, comments.
public struct FilesClient: Sendable {
    public var list: @Sendable (_ businessID: String, _ path: String?) async throws -> (root: String, entries: [FileEntry])
    public var text: @Sendable (_ businessID: String, _ path: String) async throws -> FileText
    public var bytes: @Sendable (_ businessID: String, _ path: String) async throws -> FileBytes
    public var save: @Sendable (_ businessID: String, _ path: String, _ content: String, _ expectedRevision: String?) async throws -> FileSave
    public var saveBytes: @Sendable (_ businessID: String, _ path: String, _ data: Data, _ expected: FileExpectation) async throws -> FileSave
    public var comment: @Sendable (_ businessID: String, _ path: String, _ employee: String, [FileComment]) async throws -> Void

    public init(
        list: @escaping @Sendable (String, String?) async throws -> (root: String, entries: [FileEntry]),
        text: @escaping @Sendable (String, String) async throws -> FileText,
        bytes: @escaping @Sendable (String, String) async throws -> FileBytes,
        save: @escaping @Sendable (String, String, String, String?) async throws -> FileSave,
        saveBytes: @escaping @Sendable (String, String, Data, FileExpectation) async throws -> FileSave,
        comment: @escaping @Sendable (String, String, String, [FileComment]) async throws -> Void
    ) {
        self.list = list
        self.text = text
        self.bytes = bytes
        self.save = save
        self.saveBytes = saveBytes
        self.comment = comment
    }

    public static func live(_ hub: SessionHub) -> Self {
        Self(
            list: { business, path in try await hub.call { api, session in try await api.files(session, businessID: business, path: path) } },
            text: { business, path in try await hub.call { api, session in try await api.fileText(session, businessID: business, path: path) } },
            bytes: { business, path in try await hub.call { api, session in try await api.fileBytes(session, businessID: business, path: path) } },
            save: { business, path, content, revision in
                try await hub.call { api, session in try await api.saveFile(session, businessID: business, path: path, content: content, expectedRevision: revision) }
            },
            saveBytes: { business, path, data, expected in
                try await hub.call { api, session in try await api.saveFileBytes(session, businessID: business, path: path, data: data, expected: expected) }
            },
            comment: { business, path, employee, comments in
                try await hub.call { api, session in try await api.commentOnFile(session, businessID: business, path: path, employee: employee, comments: comments) }
            }
        )
    }

    /// No Mac host: tests and previews.
    public static let none = Self(
        list: { _, _ in ("", []) },
        text: { _, path in FileText(path: path, content: "", revision: "") },
        bytes: { _, _ in FileBytes(data: Data(), revision: "") },
        save: { _, _, _, _ in .saved(revision: "") },
        saveBytes: { _, _, _, _ in .saved(revision: "") },
        comment: { _, _, _, _ in }
    )
}

nonisolated enum FilesClientKey: DependencyKey {
    static let liveValue = FilesClient.live(.shared)
    static let testValue = FilesClient.none
    static let previewValue = FilesClient.none
}

extension DependencyValues {
    public var filesClient: FilesClient {
        get { self[FilesClientKey.self] }
        set { self[FilesClientKey.self] = newValue }
    }
}
