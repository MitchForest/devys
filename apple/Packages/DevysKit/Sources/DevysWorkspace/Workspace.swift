package import ComposableArchitecture2
import Dependencies
package import DevysClient
package import Foundation

package enum Loadable<Value> {
    case loading
    case loaded(Value)
    case failed(String)

    package var value: Value? {
        if case .loaded(let value) = self { value } else { nil }
    }
}

/// The signed-in workspace: the business, its team, projects, work and conversations. The
/// conversation on screen is always the middle; the right panel shows what it is about.
@Feature
package struct Workspace {
    package init() {}

    package struct State {
        package let server: URL
        /// Who is signed in and the businesses they belong to.
        package var account: Account?
        package var businesses: [Business] = []
        package var businessID = ""
        /// The open business and its team.
        package var snapshot = WorkspaceSnapshot.empty
        package var place: Place = .home
        /// Places the owner came from, for Back (a thread opened from a channel).
        package var history: [Place] = []
        /// Temporary views over the right panel's permanent view, the top one last.
        package var layers: [OpenLayer] = []
        /// Whether each kind of place shows its permanent view, as the owner left it.
        package var panels: [Place.Kind: Bool] = [:]
        /// ⤢: the panel takes everything but the conversation's minimum while a layer is open.
        package var isWide = false
        /// Too narrow for the conversation and the panel side by side: the panel lies over the
        /// conversation, so its permanent view opens only when asked for, never by itself.
        package var isNarrow = false
        /// Asked for while narrow (⌥⌘0); going to another place clears it.
        package var isOverlayOpen = false
        /// Whether the open layer goes with the next message as a reference.
        package var isReferencing = true
        /// Counts answered turns in the conversation, so open layers read their records again.
        package var turns = 0
        /// The app is in front; the 5 s refresh runs only then.
        package var isActive = true
        package var isSidebarVisible = true
        package var isPaletteOpen = false
        /// The Head of Operations' runtime state.
        package var status: Loadable<EmployeeStatus> = .loading
        /// Each employee's latest runtime status, refreshed every tick; the sidebar's status dots derive from it.
        package var statuses: [String: EmployeeStatus] = [:]
        /// The conversation in the middle: Home's, a direct chat, a channel or a thread.
        package var main: OpenConversation?
        /// Started conversations' newest message and unread count, by key.
        package var summaries: [String: ConversationSummary] = [:]
        /// Roles to hire into, the hire in progress.
        package var team = TeamState()
        /// The work item being written in the New work item sheet.
        package var newWorkItem: WorkItemDraft?
        /// The New project sheet, while it is open.
        package var newProject: ProjectSheet?
        package var memory: Loadable<[MemoryClaim]> = .loading
        /// The business's work items and the requests waiting on the owner.
        package var work: Loadable<[WorkItem]> = .loading
        package var decisions: Loadable<[Decision]> = .loading
        package var projects: Loadable<[Project]> = .loading
        /// The app directory; installed apps with something to show are in the sidebar.
        package var apps: Loadable<[AppEntry]> = .loading
        /// What needs the owner, and work at a glance: Home's permanent view.
        package var home: Loadable<Home> = .loading
        /// The business's saved files, newest first.
        package var artifacts: [Artifact] = []
        /// The business's members, to name who took work over.
        package var members: [Person] = []
        /// The open employee's grants, loaded when its desk's Access shows.
        package var access: Loadable<AccessList> = .loading
        package var accessEmployeeID: String?
        /// The model catalog, each employee's spend, and failed model changes.
        package var models = EmployeeModels()
        package var isStopping = false
        package var notice: String?
        /// Downloaded look photos, by `LookTarget.photoKey`; looks themselves come with the records.
        package var lookPhotos: [String: Data] = [:]
        package var ownerPhoto: Data?
        package var preferences: Spawn<Preferences>?
        package var voice: VoicePhase = .idle
        package var captureID: UUID?
        package var dictationBase = TranscriptionDraft()
        /// Provisional words shown dimmed while speaking; they may still change.
        package var volatileText = ""
        package var level = 0.0
        package var isConversationMode = false
        package var voiceError: String?
        /// Messages sent from this device in this session whose answers are read aloud.
        package var repliesToSpeak: Set<String> = []

        package init(server: URL) {
            self.server = server
        }

        package var isRunning: Bool { status.value?.isRunning ?? false }
        /// Every business starts with its Head of Operations; the server lists it first.
        package var operations: Employee? { snapshot.employees.first }
        /// Where Operations' runtime and conversation live, once the team has loaded.
        package var operationsScope: EmployeeScope? {
            operations.map { EmployeeScope(businessID: businessID, employeeID: $0.id) }
        }
        package var ownerFirstName: String? {
            account?.person.displayName.split(separator: " ").first.map(String.init)
        }
    }

    package struct Action {
        package let intent: Intent

        package init(_ intent: Intent) {
            self.intent = intent
        }
    }

    package enum Intent {
        case businessSelected(String)
        case place(PlaceIntent)
        case sidebarToggled
        case paletteToggled(Bool)
        case refreshTapped
        /// The scene became active, or left the foreground.
        case activeChanged(Bool)
        case accountLoaded(Account)
        case detailLoaded(BusinessDetail)
        case tick
        case accessRequested(employeeID: String)
        case accessLoaded(employeeID: String, AccessList)
        case grantTapped(employeeID: String, capability: String, mode: AccessMode)
        case revokeTapped(employeeID: String, grantID: String)
        case pauseToggled(employeeID: String)
        case model(ModelIntent)
        case team(TeamIntent)
        case conversation(ConversationIntent)
        case workItem(WorkItemIntent)
        case project(ProjectIntent)
        case workLoaded(businessID: String, WorkRecords)
        case decisionAnswered(decisionID: String, approve: Bool)
        case workItemStateSet(workItemID: String, WorkItemState)
        case takeoverToggled(workItemID: String)
        case statusLoaded(EmployeeScope, EmployeeStatus)
        case memoryLoaded([MemoryClaim])
        case loadFailed(DevysHTTPError, memory: Bool)
        case stopTapped
        case stopFinished(String)
        case noticeDismissed
        case signOutTapped
        case teamRefreshed(BusinessDetail)
        case lookPhotosLoaded([String: Data])
        case ownerPhotoLoaded(Data?)
        case preferencesToggled(Bool)
        /// Settings opened at one section, as "Apps & connections…".
        case settingsOpened(PreferencesSection)
        case micTapped
        case conversationToggled
        case speechEvent(UUID, SpeechCaptureEvent)
        case speechFinished(UUID, String)
        case speechFailed(UUID, SpeechCaptureError)
        case speakingFinished
        case stopSpeakingTapped
        case voiceErrorDismissed
    }

    static let refreshInterval: Duration = .seconds(5)

    /// Declared here (not by the macro) so effect helpers can live in their own files.
    @FeatureBindable var store = FeatureStore<Self.State, Self.Action>()

    @Dependency(\.runtimeClient) var runtime: RuntimeClient
    @Dependency(\.sessionClient) var session: SessionClient
    @Dependency(\.continuousClock) var clock: any Clock<Duration>
    @Dependency(\.lookClient) var lookClient: LookClient
    @Dependency(\.speechCaptureClient) var capture: SpeechCaptureClient
    @Dependency(\.speechPlaybackClient) var playback: SpeechPlaybackClient
    @Dependency(\.voiceSettingsClient) var voiceSettings: VoiceSettingsClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.profileClient) var profileClient: ProfileClient
    @Dependency(\.panelsClient) var panelsClient: PanelsClient

    package var body: some Feature {
        Update { state, action in
            switch action.intent {
            case .businessSelected(let id):
                guard id != state.businessID else { return }
                select(id, state: &state)

            case .accountLoaded(let account):
                state.account = account
                state.businesses = account.businesses
                loadLookPhotos(state)
                if !account.businesses.contains(where: { $0.id == state.businessID }) {
                    let first = state.businessID.isEmpty
                    select(account.businesses.first?.id ?? "", state: &state)
                    #if DEBUG
                        // The launch place belongs to the first business, which only now is chosen.
                        if first { Self.applyQAPlace(to: &state) }
                    #endif
                }

            case .detailLoaded(let detail):
                guard detail.business.id == state.businessID else { return }
                state.snapshot.business = detail.business
                state.snapshot.employees = detail.employees
                state.members = detail.members
                state.artifacts = detail.artifacts
                loadLookPhotos(state)
                loadStatus(state)
                loadMemory(state)
                loadWork(state)
                loadSummaries(state)
                // Home's conversation is Operations', known once the team has loaded.
                openConversation(&state)

            case .tick:
                guard state.isActive else { return }
                loadStatus(state)
                loadWork(state)
                refreshConversations(state)
                // Looks and pauses changed from another client show here within one tick.
                loadAccount()
                refreshTeam(state)

            case .teamRefreshed(let detail):
                guard detail.business.id == state.businessID else { return }
                state.snapshot.business = detail.business
                state.snapshot.employees = detail.employees
                state.members = detail.members
                state.artifacts = detail.artifacts
                loadLookPhotos(state)

            case .lookPhotosLoaded(let photos):
                state.lookPhotos.merge(photos) { _, new in new }

            case .workLoaded, .decisionAnswered, .workItemStateSet, .takeoverToggled:
                reduceWork(action.intent, state: &state)

            case .place(let intent): reducePlace(intent, state: &state)

            case .project(let intent): reduceProject(intent, state: &state)

            case .team(let intent): reduceTeam(intent, state: &state)

            case .conversation(let intent): reduceConversation(intent, state: &state)

            case .workItem(let intent): reduceWorkItem(intent, state: &state)

            case .accessRequested(let employeeID):
                if state.accessEmployeeID != employeeID { state.access = .loading }
                state.accessEmployeeID = employeeID
                loadAccess(employeeID, state: state)

            case .accessLoaded(let employeeID, let list):
                guard employeeID == state.accessEmployeeID else { return }
                state.access = .loaded(list)

            case .grantTapped(let employeeID, let capability, let mode):
                changeAccess(employeeID, state: state) { runtime, scope in
                    try await runtime.grant(scope, capability, mode)
                }

            case .revokeTapped(let employeeID, let grantID):
                changeAccess(employeeID, state: state) { runtime, scope in
                    try await runtime.revoke(scope, grantID)
                }

            case .pauseToggled(let employeeID):
                togglePause(employeeID, state: &state)

            case .model(let intent): reduceModel(intent, state: &state)

            case .sidebarToggled:
                state.isSidebarVisible.toggle()

            case .paletteToggled(let open):
                state.isPaletteOpen = open

            case .activeChanged(let isActive):
                guard isActive != state.isActive else { return }
                state.isActive = isActive
                // Back in front: catch up at once rather than at the next tick.
                if isActive { refresh(state) }

            case .refreshTapped:
                refresh(state)

            case .statusLoaded(let scope, let snapshot):
                guard scope.businessID == state.businessID else { return }
                state.statuses[scope.employeeID] = snapshot
                if scope == state.operationsScope { state.status = .loaded(snapshot) }
                settleAwaiting(&state)

            case .memoryLoaded(let claims):
                state.memory = .loaded(claims)

            case .loadFailed(let error, let memory):
                loadFailed(error, memory: memory, state: &state)

            case .stopTapped:
                guard !state.isStopping, let scope = state.operationsScope else { return }
                state.isStopping = true
                let runtime = runtime
                store.addTask {
                    let notice: String
                    do {
                        notice = try await runtime.stop(scope) ? "Stop requested. Work already sent cannot be unsent." : "Nothing was running."
                    } catch let error as DevysHTTPError {
                        notice = "Couldn't stop. \(Self.message(for: error))"
                    } catch {
                        notice = "Couldn't stop. Try again."
                    }
                    try store.send(Action(.stopFinished(notice)))
                    try await status(runtime, scope)
                }

            case .stopFinished(let notice):
                state.isStopping = false
                state.notice = notice

            case .noticeDismissed:
                state.notice = nil

            case .signOutTapped:
                let session = session
                store.addTask { await session.signOut() }

            case .ownerPhotoLoaded(let photo):
                state.ownerPhoto = photo

            case .settingsOpened(let section):
                Self.openSettings(at: section, state: &state)

            case .preferencesToggled(let open):
                if open {
                    Self.openSettings(at: .account, state: &state)
                } else {
                    state.preferences = nil
                }
                // A business created, or an app installed or pinned, in Settings shows when it closes.
                if !open {
                    loadAccount()
                    loadWork(state)
                }

            case .micTapped, .conversationToggled, .speechEvent, .speechFinished, .speechFailed, .speakingFinished,
                 .stopSpeakingTapped, .voiceErrorDismissed:
                reduceVoice(action.intent, state: &state)
            }
        }
        .ifLet(\.preferences) {
            Preferences()
        }
        .onMount { state in
            state.panels = Self.panels(from: panelsClient.load())
            loadAccount()
            let clock = clock
            store.addTask {
                while !Task.isCancelled {
                    try await clock.sleep(for: Self.refreshInterval)
                    try store.send(Action(.tick))
                }
            }
            let profile = profileClient
            store.addTask {
                let photo = try? await profile.photo()
                try store.send(Action(.ownerPhotoLoaded(photo.flatMap { $0 })))
            }
        }
    }

}

// MARK: - Businesses, teams and runtime status

extension Workspace {
    /// Settings for the business on screen, at a section.
    static func openSettings(at section: PreferencesSection, state: inout State) {
        var preferences = Preferences.State()
        preferences.section = section
        preferences.selectedBusinessID = state.businessID.isEmpty ? nil : state.businessID
        state.preferences = Spawn(preferences)
    }

    /// Everything the workspace shows, read again.
    func refresh(_ state: State) {
        loadAccount()
        refreshTeam(state)
        loadStatus(state)
        loadMemory(state)
        loadWork(state)
        refreshConversations(state)
    }

    func loadFailed(_ error: DevysHTTPError, memory: Bool, state: inout State) {
        // The session hub has signed the device out (any call's 401 does); sign-in replaces this.
        if error == .unauthorized { return }
        let message = Self.message(for: error)
        if memory {
            state.memory = .failed(message)
        } else if state.status.value == nil {
            state.status = .failed(message)
        } else {
            // Keep the last good snapshot visible; flag staleness instead.
            state.notice = "Showing the last update. \(message)"
        }
    }

    /// Switches to a business; its team, work and conversations load from the server.
    func select(_ id: String, state: inout State) {
        state.businessID = id
        state.snapshot = WorkspaceSnapshot(business: state.businesses.first { $0.id == id } ?? Business(id: id, name: ""), employees: [])
        state.status = .loading
        state.statuses = [:]
        if state.isConversationMode { endConversation(&state) } else if state.voice.isCapturing { cancelCapture(&state) }
        state.main = nil
        state.summaries = [:]
        state.team.hiring = nil
        state.newWorkItem = nil
        state.newProject = nil
        state.memory = .loading
        state.access = .loading
        state.accessEmployeeID = nil
        state.models.usage = [:]
        state.models.errors = [:]
        state.work = .loading
        state.decisions = .loading
        state.projects = .loading
        state.apps = .loading
        state.home = .loading
        state.artifacts = []
        state.repliesToSpeak = []
        state.place = .home
        state.history = []
        state.layers = []
        state.isWide = false
        guard !id.isEmpty else { return }
        let runtime = runtime
        store.addTask {
            do {
                try store.send(Action(.detailLoaded(try await runtime.business(id))))
            } catch let error as DevysHTTPError {
                try store.send(Action(.loadFailed(error, memory: false)))
            }
        }
    }

    func refreshTeam(_ state: State) {
        guard !state.businessID.isEmpty else { return }
        let runtime = runtime
        let id = state.businessID
        store.addTask {
            if let detail = try? await runtime.business(id) { try store.send(Action(.teamRefreshed(detail))) }
        }
    }

    /// Downloads photos for photo looks not yet on hand; each upload has its own version.
    func loadLookPhotos(_ state: State) {
        let targets = state.businesses.map { (LookTarget.business($0.id), $0.look) }
            + state.snapshot.employees.map { (LookTarget.employee(business: state.businessID, employee: $0.id), $0.look) }
        let missing = targets.compactMap { target, look -> (LookTarget, String)? in
            guard case .photo(let version) = look, state.lookPhotos[target.photoKey(version)] == nil else { return nil }
            return (target, target.photoKey(version))
        }
        guard !missing.isEmpty else { return }
        let lookClient = lookClient
        store.addTask {
            var photos: [String: Data] = [:]
            for (target, key) in missing { photos[key] = await lookClient.photo(target) }
            try store.send(Action(.lookPhotosLoaded(photos)))
        }
    }

    func loadAccount() {
        let runtime = runtime
        store.addTask {
            do {
                try store.send(Action(.accountLoaded(try await runtime.account())))
            } catch let error as DevysHTTPError {
                try store.send(Action(.loadFailed(error, memory: false)))
            }
        }
    }

    /// Operations first, whose failures show; then everyone else, whose status dot derives from it.
    func loadStatus(_ state: State) {
        guard let scope = state.operationsScope else { return }
        let others = state.snapshot.employees.dropFirst().map { EmployeeScope(businessID: state.businessID, employeeID: $0.id) }
        let runtime = runtime
        store.addTask {
            try await status(runtime, scope)
            for other in others {
                if let status = try? await runtime.status(other) { try store.send(Action(.statusLoaded(other, status))) }
            }
        }
    }

    func status(_ runtime: RuntimeClient, _ scope: EmployeeScope) async throws {
        do {
            try store.send(Action(.statusLoaded(scope, try await runtime.status(scope))))
        } catch let error as DevysHTTPError {
            try store.send(Action(.loadFailed(error, memory: false)))
        }
    }

    func loadMemory(_ state: State) {
        let id = state.businessID
        guard !id.isEmpty else { return }
        let runtime = runtime
        store.addTask {
            do {
                try store.send(Action(.memoryLoaded(try await runtime.memory(id))))
            } catch let error as DevysHTTPError {
                try store.send(Action(.loadFailed(error, memory: true)))
            }
        }
    }
}
