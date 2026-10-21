package import DevysClient

/// Where the owner is: always a conversation. Home is the direct chat with Operations; a
/// project is its channel; a thread is a work item's conversation.
package enum Place: Hashable, Sendable {
    case home
    case direct(String)
    case project(String)
    case thread(String)

    package enum Kind: String, CaseIterable, Hashable, Sendable {
        case home, direct, project, thread

        /// Whether the right panel shows by default; the owner's choice is remembered.
        package var panelByDefault: Bool { self != .direct }
    }

    package var kind: Kind {
        switch self {
        case .home: .home
        case .direct: .direct
        case .project: .project
        case .thread: .thread
        }
    }

    /// The conversation this place shows: Home's is the direct chat with Operations.
    package func conversation(operations: String?) -> ConversationKey? {
        switch self {
        case .home: operations.map(ConversationKey.direct)
        case .direct(let id): .direct(id)
        case .project(let id): .project(id)
        case .thread(let id): .work(id)
        }
    }
}

/// A temporary view stacked over the right panel's permanent view.
package enum Layer: Hashable, Sendable {
    /// A page an employee published; `updatedBy` names who replaced it while it was open.
    case artifact(String, updatedBy: String? = nil)
    case file(String)
    case app(String)
    case session(workID: String, sessionID: String)
    case browser(workID: String)
}

/// A layer on the stack; `auto` when it opened on its own, so the next one may replace it.
package struct OpenLayer: Hashable, Sendable {
    package var layer: Layer
    package var auto = false

    package init(_ layer: Layer, auto: Bool = false) {
        self.layer = layer
        self.auto = auto
    }
}

extension Ref {
    /// The page this ref names, if it names one.
    package var page: String? {
        if case .artifact(let id) = self { id } else { nil }
    }
}

extension Layer {
    /// The record a layer shows, as a ref: a page, a file or a coding session. An app's list
    /// and the browser are not records.
    package var ref: Ref? {
        switch self {
        case .artifact(let id, _): .artifact(id)
        case .file(let path): .file(path)
        case .session(_, let sessionID): .codeSession(sessionID)
        case .app, .browser: nil
        }
    }

    /// The layer that shows a record anywhere (a page or a file), from its ref.
    package init?(ref: Ref) {
        guard case .layer(let layer) = Records.open(ref) else { return nil }
        self = layer
    }
}

/// Where a record opens: a layer over the right panel, or a place.
package enum RecordTarget: Hashable, Sendable {
    case layer(Layer)
    case place(Place)
}

/// The one registry of what opens each record kind the apps declare (their manifests' `records`),
/// keyed by `<app>/<kind>` from the ref, the same rules as the web. A kind not here opens nothing.
package enum Records {
    /// `work`: the work item of the thread on screen, which a coding session belongs to.
    package typealias Opener = @Sendable (_ id: String, _ work: String?) -> RecordTarget?

    package static let registry: [String: Opener] = [
        "documents/artifact": { id, _ in .layer(.artifact(id)) },
        "documents/file": { id, _ in .layer(.file(id)) },
        "code/session": { id, work in work.map { .layer(.session(workID: $0, sessionID: id)) } },
        "work/item": { id, _ in .place(.thread(id)) },
        "work/project": { id, _ in .place(.project(id)) }
    ]

    package static func open(_ ref: Ref, work: String? = nil) -> RecordTarget? {
        registry[ref.recordKind]?(ref.id, work)
    }
}

/// What a layer is, in words and as a ref: its header, and the reference sent with a message.
package struct LayerReference: Equatable, Sendable {
    package let title: String
    package let ref: Ref?

    package init(title: String, ref: Ref?) {
        self.title = title
        self.ref = ref
    }

    /// The line appended to a message sent while the layer is open.
    package var line: String { "\n\n_Viewing: \(title)\(ref.map { " (\($0))" } ?? "")_" }
}

/// Work by where it stands, as a project's overview groups it.
package enum WorkGroup: String, CaseIterable, Hashable, Sendable {
    case needsYou = "Needs you"
    case inProgress = "In progress"
    case waiting = "Waiting"
    case done = "Done"
}
