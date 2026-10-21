public import Dependencies
public import Foundation

public enum SessionPhase: Equatable, Sendable {
    case signedOut
    case signedIn(server: URL)
}

/// Device sign-in. The root feature routes on `phases`; sign-in and sign-out
/// only change the session, never the route directly.
public struct SessionClient: Sendable {
    public var phases: @Sendable () -> AsyncStream<SessionPhase>
    public var signIn: @Sendable (_ server: URL, _ code: String) async throws -> Void
    public var signOut: @Sendable () async -> Void
    /// The server rejected the session; forget it locally without calling the server.
    public var expire: @Sendable () async -> Void

    public init(
        phases: @escaping @Sendable () -> AsyncStream<SessionPhase>,
        signIn: @escaping @Sendable (URL, String) async throws -> Void,
        signOut: @escaping @Sendable () async -> Void,
        expire: @escaping @Sendable () async -> Void
    ) {
        self.phases = phases
        self.signIn = signIn
        self.signOut = signOut
        self.expire = expire
    }
}

/// Live data: who is signed in, their businesses and teams, and each employee's
/// runtime and conversation. Calls use the stored device session; features never hold the token.
public struct RuntimeClient: Sendable {
    public var account: @Sendable () async throws -> Account
    public var business: @Sendable (_ id: String) async throws -> BusinessDetail
    public var createBusiness: @Sendable (NewBusiness) async throws -> Business
    public var updateBusiness: @Sendable (_ id: String, _ name: String?, _ brief: String?) async throws -> Business
    public var devices: @Sendable () async throws -> [Device]
    public var issueDeviceCode: @Sendable () async throws -> DeviceCode
    public var revokeDevice: @Sendable (_ id: String) async throws -> Void
    public var roles: @Sendable () async throws -> [RoleTemplate]
    public var hire: @Sendable (_ businessID: String, Hire) async throws -> Employee
    public var updateProfile: @Sendable (EmployeeScope, ProfileChange) async throws -> Void
    /// Returns the employee who took over the open work.
    public var retire: @Sendable (EmployeeScope, _ reassignTo: String) async throws -> String
    public var status: @Sendable (EmployeeScope) async throws -> EmployeeStatus
    public var stop: @Sendable (EmployeeScope) async throws -> Bool
    public var memory: @Sendable (_ businessID: String) async throws -> [MemoryClaim]
    /// Started conversations with their newest message and unread count.
    public var conversations: @Sendable (_ businessID: String) async throws -> [ConversationSummary]
    public var conversation: @Sendable (_ businessID: String, ConversationKey, _ before: String?) async throws -> ConversationPage
    public var postMessage: @Sendable (_ businessID: String, ConversationKey, NewMessage) async throws -> PostedMessage
    public var markRead: @Sendable (_ businessID: String, ConversationKey, _ seenAt: String) async throws -> Void
    public var follow: @Sendable (_ businessID: String, ConversationKey, _ on: Bool) async throws -> Void
    /// A tapback on a message, addressed to the employee who wrote it.
    public var react: @Sendable (EmployeeScope, Reaction) async throws -> Void
    public var access: @Sendable (EmployeeScope) async throws -> AccessList
    public var grant: @Sendable (EmployeeScope, _ capability: String, AccessMode) async throws -> Void
    public var revoke: @Sendable (EmployeeScope, _ grantID: String) async throws -> Void
    public var setPaused: @Sendable (EmployeeScope, Bool) async throws -> Void
    public var models: @Sendable () async throws -> ModelCatalog
    /// Returns the model the server saved.
    public var setModel: @Sendable (EmployeeScope, _ model: String) async throws -> String
    public var work: @Sendable (_ businessID: String) async throws -> [WorkItem]
    public var createWorkItem: @Sendable (_ businessID: String, NewWorkItem) async throws -> WorkItem
    public var updateWorkItem: @Sendable (_ businessID: String, _ workItemID: String, WorkItemChange) async throws -> WorkItem
    public var setTakeover: @Sendable (_ businessID: String, _ workItemID: String, _ takeOver: Bool) async throws -> Void
    public var decisions: @Sendable (_ businessID: String) async throws -> [Decision]
    /// One work item's requests, answered ones included.
    public var workDecisions: @Sendable (_ businessID: String, _ workItemID: String) async throws -> [Decision]
    public var answer: @Sendable (_ businessID: String, _ decisionID: String, _ approve: Bool) async throws -> Void
    public var projects: @Sendable (_ businessID: String) async throws -> [Project]
    public var createProject: @Sendable (_ businessID: String, ProjectChange) async throws -> Project
    public var updateProject: @Sendable (_ businessID: String, _ projectID: String, ProjectChange) async throws -> Void
    public var addToProject: @Sendable (_ businessID: String, _ projectID: String, _ ref: Ref) async throws -> Void
    public var removeFromProject: @Sendable (_ businessID: String, _ projectID: String, _ itemID: String) async throws -> Void
    /// The app directory, and what this business has installed and pinned.
    public var apps: @Sendable (_ businessID: String) async throws -> [AppEntry]
    public var installApp: @Sendable (_ businessID: String, _ appID: String, _ install: Bool) async throws -> Void
    public var pinApp: @Sendable (_ businessID: String, _ appID: String, _ pinned: Bool) async throws -> Void
    /// What needs the owner, and work at a glance.
    public var home: @Sendable (_ businessID: String) async throws -> Home
    public var artifactText: @Sendable (_ businessID: String, _ artifactID: String) async throws -> String
    public var googleConnection: @Sendable (_ businessID: String) async throws -> GoogleConnection

    public init(
        account: @escaping @Sendable () async throws -> Account,
        business: @escaping @Sendable (String) async throws -> BusinessDetail,
        createBusiness: @escaping @Sendable (NewBusiness) async throws -> Business = { _ in throw DevysHTTPError.unauthorized },
        updateBusiness: @escaping @Sendable (String, String?, String?) async throws -> Business = { id, name, brief in
            Business(id: id, name: name ?? "", brief: brief ?? "")
        },
        devices: @escaping @Sendable () async throws -> [Device] = { [] },
        issueDeviceCode: @escaping @Sendable () async throws -> DeviceCode = { throw DevysHTTPError.unauthorized },
        revokeDevice: @escaping @Sendable (String) async throws -> Void = { _ in },
        roles: @escaping @Sendable () async throws -> [RoleTemplate] = { [] },
        hire: @escaping @Sendable (String, Hire) async throws -> Employee = { _, _ in throw DevysHTTPError.unauthorized },
        updateProfile: @escaping @Sendable (EmployeeScope, ProfileChange) async throws -> Void = { _, _ in },
        retire: @escaping @Sendable (EmployeeScope, String) async throws -> String = { _, successor in successor },
        status: @escaping @Sendable (EmployeeScope) async throws -> EmployeeStatus,
        stop: @escaping @Sendable (EmployeeScope) async throws -> Bool,
        memory: @escaping @Sendable (String) async throws -> [MemoryClaim],
        conversations: @escaping @Sendable (String) async throws -> [ConversationSummary] = { _ in [] },
        conversation: @escaping @Sendable (String, ConversationKey, String?) async throws -> ConversationPage = { _, _, _ in
            ConversationPage(messages: [], respondent: nil)
        },
        postMessage: @escaping @Sendable (String, ConversationKey, NewMessage) async throws -> PostedMessage = { _, key, message in
            PostedMessage(
                message: ConversationMessage(id: message.id, conversation: key.rawValue, author: "person:preview", text: message.text, createdAt: Date.now.formatted(.iso8601)),
                recipients: []
            )
        },
        markRead: @escaping @Sendable (String, ConversationKey, String) async throws -> Void = { _, _, _ in },
        follow: @escaping @Sendable (String, ConversationKey, Bool) async throws -> Void = { _, _, _ in },
        react: @escaping @Sendable (EmployeeScope, Reaction) async throws -> Void = { _, _ in },
        access: @escaping @Sendable (EmployeeScope) async throws -> AccessList = { _ in AccessList(grants: [], available: []) },
        grant: @escaping @Sendable (EmployeeScope, String, AccessMode) async throws -> Void = { _, _, _ in },
        revoke: @escaping @Sendable (EmployeeScope, String) async throws -> Void = { _, _ in },
        setPaused: @escaping @Sendable (EmployeeScope, Bool) async throws -> Void = { _, _ in },
        models: @escaping @Sendable () async throws -> ModelCatalog = { ModelCatalog(defaults: .init(employee: "", background: ""), models: []) },
        setModel: @escaping @Sendable (EmployeeScope, String) async throws -> String = { _, model in model },
        work: @escaping @Sendable (String) async throws -> [WorkItem] = { _ in [] },
        createWorkItem: @escaping @Sendable (String, NewWorkItem) async throws -> WorkItem = { _, newItem in
            WorkItem(id: UUID().uuidString, ownerEmployeeID: newItem.owner, title: newItem.title)
        },
        updateWorkItem: @escaping @Sendable (String, String, WorkItemChange) async throws -> WorkItem = { _, _, _ in
            throw DevysHTTPError.unauthorized
        },
        setTakeover: @escaping @Sendable (String, String, Bool) async throws -> Void = { _, _, _ in },
        decisions: @escaping @Sendable (String) async throws -> [Decision] = { _ in [] },
        workDecisions: @escaping @Sendable (String, String) async throws -> [Decision] = { _, _ in [] },
        answer: @escaping @Sendable (String, String, Bool) async throws -> Void = { _, _, _ in },
        projects: @escaping @Sendable (String) async throws -> [Project] = { _ in [] },
        createProject: @escaping @Sendable (String, ProjectChange) async throws -> Project = { _, project in
            Project(id: UUID().uuidString, name: project.name, leadEmployeeID: project.lead, memberIDs: project.members)
        },
        updateProject: @escaping @Sendable (String, String, ProjectChange) async throws -> Void = { _, _, _ in },
        addToProject: @escaping @Sendable (String, String, Ref) async throws -> Void = { _, _, _ in },
        removeFromProject: @escaping @Sendable (String, String, String) async throws -> Void = { _, _, _ in },
        apps: @escaping @Sendable (String) async throws -> [AppEntry] = { _ in [] },
        installApp: @escaping @Sendable (String, String, Bool) async throws -> Void = { _, _, _ in },
        pinApp: @escaping @Sendable (String, String, Bool) async throws -> Void = { _, _, _ in },
        home: @escaping @Sendable (String) async throws -> Home = { _ in Home() },
        artifactText: @escaping @Sendable (String, String) async throws -> String = { _, _ in "" },
        googleConnection: @escaping @Sendable (String) async throws -> GoogleConnection = { _ in GoogleConnection(configured: false, connected: false) }
    ) {
        self.account = account
        self.business = business
        self.createBusiness = createBusiness
        self.updateBusiness = updateBusiness
        self.devices = devices
        self.issueDeviceCode = issueDeviceCode
        self.revokeDevice = revokeDevice
        self.roles = roles
        self.hire = hire
        self.updateProfile = updateProfile
        self.retire = retire
        self.status = status
        self.stop = stop
        self.memory = memory
        self.conversations = conversations
        self.conversation = conversation
        self.postMessage = postMessage
        self.markRead = markRead
        self.follow = follow
        self.react = react
        self.access = access
        self.grant = grant
        self.revoke = revoke
        self.setPaused = setPaused
        self.models = models
        self.setModel = setModel
        self.work = work
        self.createWorkItem = createWorkItem
        self.updateWorkItem = updateWorkItem
        self.setTakeover = setTakeover
        self.decisions = decisions
        self.workDecisions = workDecisions
        self.answer = answer
        self.projects = projects
        self.createProject = createProject
        self.updateProject = updateProject
        self.addToProject = addToProject
        self.removeFromProject = removeFromProject
        self.apps = apps
        self.installApp = installApp
        self.pinApp = pinApp
        self.home = home
        self.artifactText = artifactText
        self.googleConnection = googleConnection
    }
}

/// One owner of the device session for every live client.
public actor SessionHub {
    public static let shared = SessionHub(api: .live, store: .keychain())

    private let api: DevysHTTPClient
    private let store: DeviceSessionStore
    private var stored: DeviceSession??
    private var subscribers: [UUID: AsyncStream<SessionPhase>.Continuation] = [:]

    public init(api: DevysHTTPClient, store: DeviceSessionStore) {
        self.api = api
        self.store = store
    }

    /// Read lazily on the actor, never on the main thread: a Keychain prompt
    /// must not block the first window.
    private var session: DeviceSession? {
        get {
            if let stored { return stored }
            let loaded = store.load()
            stored = .some(loaded)
            return loaded
        }
        set { stored = .some(newValue) }
    }

    public func signIn(server: URL, code: String) async throws {
        let issued = try await api.enroll(server: server, code: code, name: await DeviceName.current())
        try store.save(issued)
        publish(issued)
    }

    public func signOut() async {
        if let session { try? await api.signOut(session) }
        expire()
    }

    public func expire() {
        store.clear()
        publish(nil)
    }

    public func current() throws -> DeviceSession {
        guard let session else { throw DevysHTTPError.unauthorized }
        return session
    }

    public func call<Value: Sendable>(
        _ operation: @Sendable (DevysHTTPClient, DeviceSession) async throws -> Value
    ) async throws -> Value {
        try await operation(api, current())
    }

    func subscribe(_ continuation: AsyncStream<SessionPhase>.Continuation) {
        let id = UUID()
        subscribers[id] = continuation
        continuation.yield(phase)
        continuation.onTermination = { _ in Task { await self.unsubscribe(id) } }
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    private var phase: SessionPhase {
        session.map { .signedIn(server: $0.server) } ?? .signedOut
    }

    private func publish(_ next: DeviceSession?) {
        session = next
        for continuation in subscribers.values { continuation.yield(phase) }
    }
}

extension SessionClient {
    public static func live(_ hub: SessionHub) -> Self {
        Self(
            phases: {
                AsyncStream { continuation in
                    Task { await hub.subscribe(continuation) }
                }
            },
            signIn: { server, code in try await hub.signIn(server: server, code: code) },
            signOut: { await hub.signOut() },
            expire: { await hub.expire() }
        )
    }

    public static let unimplemented = Self(
        phases: { AsyncStream { $0.finish() } },
        signIn: { _, _ in throw DevysHTTPError.unauthorized },
        signOut: {},
        expire: {}
    )

    public static let signedInPreview = Self(
        phases: { AsyncStream { $0.yield(.signedIn(server: URL(string: "http://127.0.0.1:5173")!)) } },
        signIn: { _, _ in },
        signOut: {},
        expire: {}
    )
}

extension RuntimeClient {
    public static func live(_ hub: SessionHub) -> Self {
        Self(
            account: { try await hub.call { api, session in try await api.account(session) } },
            business: { id in try await hub.call { api, session in try await api.business(session, id: id) } },
            createBusiness: { business in try await hub.call { api, session in try await api.createBusiness(session, business) } },
            updateBusiness: { id, name, brief in
                try await hub.call { api, session in try await api.updateBusiness(session, id: id, name: name, brief: brief) }
            },
            devices: { try await hub.call { api, session in try await api.devices(session) } },
            issueDeviceCode: { try await hub.call { api, session in try await api.issueDeviceCode(session) } },
            revokeDevice: { id in try await hub.call { api, session in try await api.revokeDevice(session, id: id) } },
            roles: { try await hub.call { api, session in try await api.roles(session) } },
            hire: { id, hire in try await hub.call { api, session in try await api.hire(session, businessID: id, hire) } },
            updateProfile: { scope, change in try await hub.call { api, session in try await api.updateProfile(session, scope, change) } },
            retire: { scope, successor in try await hub.call { api, session in try await api.retire(session, scope, reassignTo: successor) } },
            status: { scope in try await hub.call { api, session in try await api.status(session, scope) } },
            stop: { scope in try await hub.call { api, session in try await api.stop(session, scope) } },
            memory: { id in try await hub.call { api, session in try await api.memory(session, businessID: id) } },
            conversations: { id in try await hub.call { api, session in try await api.conversations(session, businessID: id) } },
            conversation: { id, key, before in
                try await hub.call { api, session in try await api.conversation(session, businessID: id, key: key, before: before) }
            },
            postMessage: { id, key, message in
                try await hub.call { api, session in try await api.postMessage(session, businessID: id, key: key, message) }
            },
            markRead: { id, key, seen in try await hub.call { api, session in try await api.markRead(session, businessID: id, key: key, at: seen) } },
            follow: { id, key, following in
                try await hub.call { api, session in try await api.follow(session, businessID: id, key: key, following: following) }
            },
            react: { scope, reaction in try await hub.call { api, session in try await api.react(session, scope, reaction) } },
            access: { scope in try await hub.call { api, session in try await api.access(session, scope) } },
            grant: { scope, capability, mode in
                try await hub.call { api, session in try await api.grant(session, scope, capability: capability, mode: mode) }
            },
            revoke: { scope, id in try await hub.call { api, session in try await api.revoke(session, scope, grantID: id) } },
            setPaused: { scope, paused in try await hub.call { api, session in try await api.setPaused(session, scope, paused: paused) } },
            models: { try await hub.call { api, session in try await api.models(session) } },
            setModel: { scope, model in try await hub.call { api, session in try await api.setModel(session, scope, model: model) } },
            work: { id in try await hub.call { api, session in try await api.work(session, businessID: id) } },
            createWorkItem: { id, newItem in try await hub.call { api, session in try await api.createWorkItem(session, businessID: id, newItem) } },
            updateWorkItem: { id, item, change in
                try await hub.call { api, session in try await api.updateWorkItem(session, businessID: id, id: item, change) }
            },
            setTakeover: { id, workItem, takeOver in
                try await hub.call { api, session in try await api.setTakeover(session, businessID: id, id: workItem, takeOver: takeOver) }
            },
            decisions: { id in try await hub.call { api, session in try await api.decisions(session, businessID: id) } },
            workDecisions: { id, workItem in
                try await hub.call { api, session in try await api.decisions(session, businessID: id, workItemID: workItem) }
            },
            answer: { id, decision, approve in
                try await hub.call { api, session in try await api.answer(session, businessID: id, decisionID: decision, approve: approve) }
            },
            projects: { id in try await hub.call { api, session in try await api.projects(session, businessID: id) } },
            createProject: { id, project in try await hub.call { api, session in try await api.createProject(session, businessID: id, project) } },
            updateProject: { id, project, change in
                try await hub.call { api, session in try await api.updateProject(session, businessID: id, projectID: project, change) }
            },
            addToProject: { id, project, ref in
                try await hub.call { api, session in try await api.addToProject(session, businessID: id, projectID: project, ref: ref) }
            },
            removeFromProject: { id, project, item in
                try await hub.call { api, session in try await api.removeFromProject(session, businessID: id, projectID: project, itemID: item) }
            },
            apps: { id in try await hub.call { api, session in try await api.apps(session, businessID: id) } },
            installApp: { id, app, install in
                try await hub.call { api, session in try await api.installApp(session, businessID: id, appID: app, install: install) }
            },
            pinApp: { id, app, pinned in try await hub.call { api, session in try await api.pinApp(session, businessID: id, appID: app, pinned: pinned) } },
            home: { id in try await hub.call { api, session in try await api.home(session, businessID: id) } },
            artifactText: { id, artifact in
                try await hub.call { api, session in try await api.artifactText(session, businessID: id, artifactID: artifact) }
            },
            googleConnection: { id in try await hub.call { api, session in try await api.googleConnection(session, businessID: id) } }
        )
    }

    public static let unimplemented = Self(
        account: { throw DevysHTTPError.unauthorized },
        business: { _ in throw DevysHTTPError.unauthorized },
        status: { _ in throw DevysHTTPError.unauthorized },
        stop: { _ in throw DevysHTTPError.unauthorized },
        memory: { _ in throw DevysHTTPError.unauthorized }
    )
}

nonisolated enum SessionClientKey: DependencyKey {
    static let liveValue = SessionClient.live(.shared)
    static let testValue = SessionClient.unimplemented
    static let previewValue = SessionClient.signedInPreview
}

nonisolated enum RuntimeClientKey: DependencyKey {
    static let liveValue = RuntimeClient.live(.shared)
    static let testValue = RuntimeClient.unimplemented
    #if DEBUG
        static let previewValue = RuntimeClient.fixture
    #else
        static let previewValue = RuntimeClient.unimplemented
    #endif
}

nonisolated enum LookClientKey: DependencyKey {
    static let liveValue = LookClient.live(.shared)
    static let testValue = LookClient.inert
    static let previewValue = LookClient.inert
}

nonisolated enum ProfileClientKey: DependencyKey {
    static let liveValue = ProfileClient.live(.shared)
    static let testValue = ProfileClient.inert
    static let previewValue = ProfileClient.inert
}

extension DependencyValues {
    public var lookClient: LookClient {
        get { self[LookClientKey.self] }
        set { self[LookClientKey.self] = newValue }
    }

    public var profileClient: ProfileClient {
        get { self[ProfileClientKey.self] }
        set { self[ProfileClientKey.self] = newValue }
    }

    public var sessionClient: SessionClient {
        get { self[SessionClientKey.self] }
        set { self[SessionClientKey.self] = newValue }
    }

    public var runtimeClient: RuntimeClient {
        get { self[RuntimeClientKey.self] }
        set { self[RuntimeClientKey.self] = newValue }
    }
}
