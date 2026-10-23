public import Dependencies
public import Foundation

public enum SessionPhase: Equatable, Sendable {
    case signedOut
    case signedIn(server: URL)
}

/// Device sign-in, with nothing to type. The root feature routes on `phases`; signing in and out
/// only change the session, never the route directly.
public struct SessionClient: Sendable {
    public var phases: @Sendable () -> AsyncStream<SessionPhase>
    /// On the Mac running Devys, signs in as the Mac's owner and returns true; false elsewhere.
    public var signInAsOwner: @Sendable () async throws -> Bool
    /// Asks a Mac to let this device join; the token it chose stays in the session hub.
    public var requestJoin: @Sendable (FoundMac) async throws -> JoinTicket
    /// Waits for the answer; allowed signs this device in.
    public var awaitJoin: @Sendable (JoinTicket) async throws -> JoinOutcome
    public var signOut: @Sendable () async -> Void

    public init(
        phases: @escaping @Sendable () -> AsyncStream<SessionPhase>,
        signInAsOwner: @escaping @Sendable () async throws -> Bool = { false },
        requestJoin: @escaping @Sendable (FoundMac) async throws -> JoinTicket = { _ in throw DevysHTTPError.unauthorized },
        awaitJoin: @escaping @Sendable (JoinTicket) async throws -> JoinOutcome = { _ in .expired },
        signOut: @escaping @Sendable () async -> Void
    ) {
        self.phases = phases
        self.signInAsOwner = signInAsOwner
        self.requestJoin = requestJoin
        self.awaitJoin = awaitJoin
        self.signOut = signOut
    }
}

/// Live data: who is signed in, their businesses and teams, and each employee's
/// runtime and conversation. Calls use the stored device session; features never hold the token.
public struct RuntimeClient: Sendable {
    public var account: @Sendable () async throws -> Account
    /// Changes the name the signed-in person goes by; returns the account as saved.
    public var rename: @Sendable (_ name: String) async throws -> Account
    public var business: @Sendable (_ id: String) async throws -> BusinessDetail
    public var createBusiness: @Sendable (NewBusiness) async throws -> Business
    public var updateBusiness: @Sendable (_ id: String, _ name: String?, _ brief: String?) async throws -> Business
    /// The business's export, newline-delimited JSON.
    public var exportBusiness: @Sendable (_ id: String) async throws -> Data
    public var devices: @Sendable () async throws -> [Device]
    public var revokeDevice: @Sendable (_ id: String) async throws -> Void
    /// What this Devys calls itself and where other devices reach it (the QR code).
    public var hello: @Sendable () async throws -> Hello
    /// A one-time link that signs a browser in as this person.
    public var signInLink: @Sendable () async throws -> URL
    /// Devices asking to join now.
    public var joins: @Sendable () async throws -> [JoinRequest]
    /// Allows or denies a device; allowed with an app's key, that key to endorse.
    public var answerJoin: @Sendable (_ id: String, _ allow: Bool) async throws -> DeviceKey?
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
    /// Starts a plan that waits for the owner's Start.
    public var startWork: @Sendable (_ businessID: String, _ workItemID: String) async throws -> WorkItem
    public var answer: @Sendable (_ businessID: String, _ decisionID: String, _ approve: Bool) async throws -> Void
    /// Answers a file request with the file the owner chose; it goes into the business folder.
    public var sendFile: @Sendable (_ businessID: String, _ decisionID: String, ChosenFile) async throws -> Void
    public var projects: @Sendable (_ businessID: String) async throws -> [Project]
    public var createProject: @Sendable (_ businessID: String, ProjectChange) async throws -> Project
    public var addToProject: @Sendable (_ businessID: String, _ projectID: String, _ ref: Ref) async throws -> Void
    public var removeFromProject: @Sendable (_ businessID: String, _ projectID: String, _ itemID: String) async throws -> Void
    /// The app directory, and what this business has installed and pinned.
    public var apps: @Sendable (_ businessID: String) async throws -> [AppEntry]
    public var installApp: @Sendable (_ businessID: String, _ appID: String, _ install: Bool) async throws -> Void
    public var pinApp: @Sendable (_ businessID: String, _ appID: String, _ pinned: Bool) async throws -> Void
    /// What needs the owner, and work at a glance.
    public var home: @Sendable (_ businessID: String) async throws -> Home
    /// The business's routines; desks and overviews filter them.
    public var routines: @Sendable (_ businessID: String) async throws -> [Routine]
    /// Pauses or resumes a routine; returns it as the server saved it.
    public var setRoutinePaused: @Sendable (_ businessID: String, _ routineID: String, _ paused: Bool) async throws -> Routine
    public var artifactText: @Sendable (_ businessID: String, _ artifactID: String) async throws -> String
    public var googleConnection: @Sendable (_ businessID: String) async throws -> GoogleConnection
    /// The business's secrets by name; adding and removing answer the list as it now stands.
    public var secrets: @Sendable (_ businessID: String) async throws -> [SecretEntry]
    public var addSecret: @Sendable (_ businessID: String, NewSecret) async throws -> [SecretEntry]
    public var removeSecret: @Sendable (_ businessID: String, _ name: String) async throws -> [SecretEntry]
    /// Apps for a query: the business's own and the MCP Registry's.
    public var searchApps: @Sendable (_ businessID: String, _ query: String) async throws -> [FoundApp]
    /// Adds a remote app (by what search found, or its address), not yet connected.
    public var addApp: @Sendable (_ businessID: String, _ app: String) async throws -> AppEntry
    /// Starts connecting a remote app: its provider's sign-in page, or nil when it needs none.
    public var connectApp: @Sendable (_ businessID: String, _ appID: String) async throws -> Connecting
    public var appReview: @Sendable (_ businessID: String, _ appID: String) async throws -> AppReview
    /// Turns a remote app on (or changes it): the owner's choices are its policy.
    public var acceptApp: @Sendable (_ businessID: String, _ appID: String, AppAcceptance) async throws -> AppEntry
    /// A remote app's logo bytes, from the path the server gave.
    public var appLogo: @Sendable (_ path: String) async throws -> Data

    public init(
        account: @escaping @Sendable () async throws -> Account,
        rename: @escaping @Sendable (String) async throws -> Account = { _ in throw DevysHTTPError.unauthorized },
        business: @escaping @Sendable (String) async throws -> BusinessDetail,
        createBusiness: @escaping @Sendable (NewBusiness) async throws -> Business = { _ in throw DevysHTTPError.unauthorized },
        updateBusiness: @escaping @Sendable (String, String?, String?) async throws -> Business = { id, name, brief in
            Business(id: id, name: name ?? "", brief: brief ?? "")
        },
        exportBusiness: @escaping @Sendable (String) async throws -> Data = { _ in Data() },
        devices: @escaping @Sendable () async throws -> [Device] = { [] },
        revokeDevice: @escaping @Sendable (String) async throws -> Void = { _ in },
        hello: @escaping @Sendable () async throws -> Hello = { throw DevysHTTPError.unauthorized },
        signInLink: @escaping @Sendable () async throws -> URL = { throw DevysHTTPError.unauthorized },
        joins: @escaping @Sendable () async throws -> [JoinRequest] = { [] },
        answerJoin: @escaping @Sendable (String, Bool) async throws -> DeviceKey? = { _, _ in nil },
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
                message: ConversationMessage(id: message.id, conversation: key.rawValue, author: "person:preview", text: message.text, createdAt: ServerDate.format(Date.now)),
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
        startWork: @escaping @Sendable (String, String) async throws -> WorkItem = { _, _ in throw DevysHTTPError.unauthorized },
        answer: @escaping @Sendable (String, String, Bool) async throws -> Void = { _, _, _ in },
        sendFile: @escaping @Sendable (String, String, ChosenFile) async throws -> Void = { _, _, _ in },
        projects: @escaping @Sendable (String) async throws -> [Project] = { _ in [] },
        createProject: @escaping @Sendable (String, ProjectChange) async throws -> Project = { _, project in
            Project(id: UUID().uuidString, name: project.name, leadEmployeeID: project.lead, memberIDs: project.members)
        },
        addToProject: @escaping @Sendable (String, String, Ref) async throws -> Void = { _, _, _ in },
        removeFromProject: @escaping @Sendable (String, String, String) async throws -> Void = { _, _, _ in },
        apps: @escaping @Sendable (String) async throws -> [AppEntry] = { _ in [] },
        installApp: @escaping @Sendable (String, String, Bool) async throws -> Void = { _, _, _ in },
        pinApp: @escaping @Sendable (String, String, Bool) async throws -> Void = { _, _, _ in },
        home: @escaping @Sendable (String) async throws -> Home = { _ in Home() },
        routines: @escaping @Sendable (String) async throws -> [Routine] = { _ in [] },
        setRoutinePaused: @escaping @Sendable (String, String, Bool) async throws -> Routine = { _, _, _ in throw DevysHTTPError.unauthorized },
        artifactText: @escaping @Sendable (String, String) async throws -> String = { _, _ in "" },
        googleConnection: @escaping @Sendable (String) async throws -> GoogleConnection = { _ in GoogleConnection(configured: false, connected: false) },
        secrets: @escaping @Sendable (String) async throws -> [SecretEntry] = { _ in [] },
        addSecret: @escaping @Sendable (String, NewSecret) async throws -> [SecretEntry] = { _, secret in
            [SecretEntry(name: secret.name, kind: { if case .card = secret.value { .spend } else { .secret } }())]
        },
        removeSecret: @escaping @Sendable (String, String) async throws -> [SecretEntry] = { _, _ in [] },
        searchApps: @escaping @Sendable (String, String) async throws -> [FoundApp] = { _, _ in [] },
        addApp: @escaping @Sendable (String, String) async throws -> AppEntry = { _, _ in throw DevysHTTPError.unauthorized },
        connectApp: @escaping @Sendable (String, String) async throws -> Connecting = { _, _ in throw DevysHTTPError.unauthorized },
        appReview: @escaping @Sendable (String, String) async throws -> AppReview = { _, _ in throw DevysHTTPError.unauthorized },
        acceptApp: @escaping @Sendable (String, String, AppAcceptance) async throws -> AppEntry = { _, _, _ in throw DevysHTTPError.unauthorized },
        appLogo: @escaping @Sendable (String) async throws -> Data = { _ in Data() }
    ) {
        self.account = account
        self.rename = rename
        self.business = business
        self.createBusiness = createBusiness
        self.updateBusiness = updateBusiness
        self.exportBusiness = exportBusiness
        self.devices = devices
        self.revokeDevice = revokeDevice
        self.hello = hello
        self.signInLink = signInLink
        self.joins = joins
        self.answerJoin = answerJoin
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
        self.startWork = startWork
        self.answer = answer
        self.sendFile = sendFile
        self.projects = projects
        self.createProject = createProject
        self.addToProject = addToProject
        self.removeFromProject = removeFromProject
        self.apps = apps
        self.installApp = installApp
        self.pinApp = pinApp
        self.home = home
        self.routines = routines
        self.setRoutinePaused = setRoutinePaused
        self.artifactText = artifactText
        self.googleConnection = googleConnection
        self.secrets = secrets
        self.addSecret = addSecret
        self.removeSecret = removeSecret
        self.searchApps = searchApps
        self.addApp = addApp
        self.connectApp = connectApp
        self.appReview = appReview
        self.acceptApp = acceptApp
        self.appLogo = appLogo
    }
}

/// One owner of the device session for every live client.
public actor SessionHub {
    #if DEBUG
        /// QA: `DEVYS_SESSION=memory` starts signed out with nothing kept (a first run).
        public static let shared = SessionHub(
            api: .live,
            store: ProcessInfo.processInfo.environment["DEVYS_SESSION"] == "memory" ? .inMemory() : .keychain()
        )
    #else
        public static let shared = SessionHub(api: .live, store: .keychain())
    #endif

    private let api: DevysHTTPClient
    private let store: DeviceSessionStore
    private var stored: DeviceSession??
    private var subscribers: [UUID: AsyncStream<SessionPhase>.Continuation] = [:]
    /// The tokens this device chose for its requests to join, by request; used once allowed.
    private var joining: [String: ChosenToken] = [:]

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

    /// The Mac app on the Mac running Devys signs in as the Mac's owner, proving it with the owner
    /// file only that macOS user can read. False on every other device.
    public func signInAsOwner() async throws -> Bool {
        guard let owner = OwnerFile.read() else { return false }
        let issued = try await api.localSession(owner, name: NSFullUserName(), label: await DeviceName.current())
        try store.save(issued)
        publish(issued)
        return true
    }

    /// Asks the Mac to let this device join, with the hash of a session token chosen here.
    public func requestJoin(_ mac: FoundMac, publicKey: String?) async throws -> JoinTicket {
        let chosen = ChosenToken()
        let asked = try await api.askToJoin(
            server: mac.server,
            name: await DeviceName.current() ?? "A device",
            sessionHash: chosen.hash,
            publicKey: publicKey
        )
        joining[asked.id] = chosen
        return JoinTicket(id: asked.id, mac: mac, match: asked.match)
    }

    /// Asks how the request went until it is answered or expires (two minutes). Allowed, the
    /// chosen token is this device's session.
    public func awaitJoin(_ ticket: JoinTicket) async throws -> JoinOutcome {
        guard let chosen = joining[ticket.id] else { return .expired }
        defer { joining[ticket.id] = nil }
        let giveUp = Date.now.addingTimeInterval(150)
        while Date.now < giveUp {
            try await Task.sleep(for: .milliseconds(1500))
            // A missed answer is asked again.
            switch try? await api.joinStatus(server: ticket.mac.server, id: ticket.id, token: chosen.token) {
            case "allowed":
                let session = DeviceSession(server: ticket.mac.server, token: chosen.token)
                try store.save(session)
                publish(session)
                return .allowed
            case "denied": return .denied
            case "expired": return .expired
            default: continue
            }
        }
        return .expired
    }

    public func signOut() async {
        if let session { try? await api.signOut(session) }
        expire()
    }

    /// The server rejected the session; forget it locally without calling the server.
    public func expire() {
        store.clear()
        publish(nil)
    }

    public func current() throws -> DeviceSession {
        guard let session else { throw DevysHTTPError.unauthorized }
        return session
    }

    /// Every live call goes through here, so a 401 from any of them signs the device out once.
    public func call<Value: Sendable>(
        _ operation: @Sendable (DevysHTTPClient, DeviceSession) async throws -> Value
    ) async throws -> Value {
        let session = try current()
        do {
            return try await operation(api, session)
        } catch DevysHTTPError.unauthorized {
            // Only the session that was refused; a newer sign-in stays.
            if self.session == session { expire() }
            throw DevysHTTPError.unauthorized
        }
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
    public static func live(_ hub: SessionHub, signer: DeviceSigner) -> Self {
        Self(
            phases: {
                AsyncStream { continuation in
                    Task { await hub.subscribe(continuation) }
                }
            },
            signInAsOwner: { try await hub.signInAsOwner() },
            requestJoin: { mac in
                // The app's signing key goes with the request, to be enrolled for it when allowed.
                try await hub.requestJoin(mac, publicKey: try? signer.publicKey().base64EncodedString())
            },
            awaitJoin: { ticket in try await hub.awaitJoin(ticket) },
            signOut: { await hub.signOut() }
        )
    }

    public static let unimplemented = Self(
        phases: { AsyncStream { $0.finish() } },
        signOut: {}
    )

    public static let signedInPreview = Self(
        phases: { AsyncStream { $0.yield(.signedIn(server: URL(string: "http://127.0.0.1:5173")!)) } },
        signOut: {}
    )
}

extension RuntimeClient {
    public static func live(_ hub: SessionHub) -> Self {
        Self(
            account: { try await hub.call { api, session in try await api.account(session) } },
            rename: { name in try await hub.call { api, session in try await api.rename(session, name) } },
            business: { id in try await hub.call { api, session in try await api.business(session, id: id) } },
            createBusiness: { business in try await hub.call { api, session in try await api.createBusiness(session, business) } },
            updateBusiness: { id, name, brief in
                try await hub.call { api, session in try await api.updateBusiness(session, id: id, name: name, brief: brief) }
            },
            exportBusiness: { id in try await hub.call { api, session in try await api.exportBusiness(session, id: id) } },
            devices: { try await hub.call { api, session in try await api.devices(session) } },
            revokeDevice: { id in try await hub.call { api, session in try await api.revokeDevice(session, id: id) } },
            hello: { try await hub.call { api, session in try await api.hello(server: session.server) } },
            signInLink: { try await hub.call { api, session in try await api.signInLink(session) } },
            joins: { try await hub.call { api, session in try await api.joins(session) } },
            answerJoin: { id, allow in try await hub.call { api, session in try await api.answerJoin(session, id: id, allow: allow) } },
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
            startWork: { id, workItem in
                try await hub.call { api, session in try await api.startWorkItem(session, businessID: id, id: workItem) }
            },
            answer: { id, decision, approve in
                try await hub.call { api, session in try await api.answer(session, businessID: id, decisionID: decision, approve: approve) }
            },
            sendFile: { id, decision, file in
                try await hub.call { api, session in try await api.sendFile(session, businessID: id, decisionID: decision, file) }
            },
            projects: { id in try await hub.call { api, session in try await api.projects(session, businessID: id) } },
            createProject: { id, project in try await hub.call { api, session in try await api.createProject(session, businessID: id, project) } },
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
            routines: { id in try await hub.call { api, session in try await api.routines(session, businessID: id) } },
            setRoutinePaused: { id, routine, paused in
                try await hub.call { api, session in try await api.setRoutinePaused(session, businessID: id, id: routine, paused: paused) }
            },
            artifactText: { id, artifact in
                try await hub.call { api, session in try await api.artifactText(session, businessID: id, artifactID: artifact) }
            },
            googleConnection: { id in try await hub.call { api, session in try await api.googleConnection(session, businessID: id) } },
            secrets: { id in try await hub.call { api, session in try await api.secrets(session, businessID: id) } },
            addSecret: { id, secret in try await hub.call { api, session in try await api.addSecret(session, businessID: id, secret) } },
            removeSecret: { id, name in try await hub.call { api, session in try await api.removeSecret(session, businessID: id, name: name) } },
            searchApps: { id, query in try await hub.call { api, session in try await api.searchApps(session, businessID: id, query: query) } },
            addApp: { id, app in try await hub.call { api, session in try await api.addApp(session, businessID: id, app: app) } },
            connectApp: { id, app in try await hub.call { api, session in try await api.connectApp(session, businessID: id, appID: app) } },
            appReview: { id, app in try await hub.call { api, session in try await api.appReview(session, businessID: id, appID: app) } },
            acceptApp: { id, app, acceptance in
                try await hub.call { api, session in try await api.acceptApp(session, businessID: id, appID: app, acceptance) }
            },
            appLogo: { path in try await hub.call { api, session in try await api.appLogo(session, path: path) } }
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
    static let liveValue = SessionClient.live(.shared, signer: .secureEnclave())
    static let testValue = SessionClient.unimplemented
    static let previewValue = SessionClient.signedInPreview
}

nonisolated enum DiscoveryClientKey: DependencyKey {
    static let liveValue = DiscoveryClient.live
    static let testValue = DiscoveryClient.none
    static let previewValue = DiscoveryClient.none
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

nonisolated enum SigningClientKey: DependencyKey {
    static let liveValue = SigningClient.live(.shared, signer: .secureEnclave())
    static let testValue = SigningClient.unimplemented
    static let previewValue = SigningClient.unimplemented
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

    /// This device's signing key: spend approvals and allowing the person's other devices.
    public var signingClient: SigningClient {
        get { self[SigningClientKey.self] }
        set { self[SigningClientKey.self] = newValue }
    }

    /// Macs running Devys on the local network, and the last one this device used.
    public var discoveryClient: DiscoveryClient {
        get { self[DiscoveryClientKey.self] }
        set { self[DiscoveryClientKey.self] = newValue }
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
