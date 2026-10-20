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

/// The signed-in workspace: the business, its team, work, spaces and conversations.
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
        package var page: Page = .today
        /// Chosen in the rail; it decides the sidebar. Pages never change it implicitly.
        package var destination: Destination = .home
        package var isSidebarVisible = true
        package var isInspectorVisible = true
        package var isPaletteOpen = false
        package var spaceTab: SpaceTab = .conversation
        package var employeeTab: EmployeeTab = .activity
        package var workLayout: WorkLayout = .list
        /// The Head of Operations' runtime state.
        package var status: Loadable<EmployeeStatus> = .loading
        /// Each employee's latest runtime status, refreshed every tick; presence derives from it.
        package var statuses: [String: EmployeeStatus] = [:]
        /// The DM or space conversation in the main pane.
        package var main: OpenConversation?
        /// The work item in the right panel, with its thread.
        package var panel: OpenConversation?
        /// Started conversations' newest message and unread count, by key.
        package var summaries: [String: ConversationSummary] = [:]
        /// Roles to hire into, the hire in progress.
        package var team = TeamState()
        /// The task being written in the New task sheet.
        package var newTask: TaskDraft?
        /// The business's Google Drive connection, loaded when Connections opens.
        package var google: Loadable<GoogleConnection>?
        package var memory: Loadable<[MemoryClaim]> = .loading
        /// The business's commitments and the requests waiting on the owner.
        package var work: Loadable<[Commitment]> = .loading
        package var decisions: Loadable<[Decision]> = .loading
        package var spaces: Loadable<[Space]> = .loading
        /// The business's saved files, newest first.
        package var artifacts: [Artifact] = []
        /// The business's members, to name who took work over.
        package var members: [Person] = []
        /// Text of Markdown files opened inline in a space.
        package var artifactTexts: [String: Loadable<String>] = [:]
        /// The open employee's grants, loaded when its Access tab shows.
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
        case destinationSelected(Destination)
        case pageSelected(Page)
        case sidebarToggled
        case inspectorToggled
        case paletteToggled(Bool)
        case spaceTabSelected(SpaceTab)
        case employeeTabSelected(EmployeeTab)
        case workLayoutSelected(WorkLayout)
        case refreshTapped
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
        case task(TaskIntent)
        case connectionsRequested
        case googleLoaded(Loadable<GoogleConnection>)
        case workLoaded(businessID: String, [Commitment], [Decision], [Space])
        case spaceCreateTapped(NewSpace)
        case spaceLeadChanged(spaceID: String, leadID: String)
        case spaceItemAdded(spaceID: String, kind: SpaceItem.Kind, ref: String)
        case spaceItemRemoved(spaceID: String, itemID: String)
        case artifactOpened(artifactID: String)
        case artifactTextLoaded(artifactID: String, Loadable<String>)
        case decisionAnswered(decisionID: String, approve: Bool)
        case commitmentStateSet(commitmentID: String, CommitmentState)
        case takeoverToggled(commitmentID: String)
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
        case presenceTapped(String)
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
                    select(account.businesses.first?.id ?? "", state: &state)
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
                openConversation(for: state.page, state: &state)

            case .tick:
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

            case .workLoaded, .decisionAnswered, .commitmentStateSet, .takeoverToggled, .spaceCreateTapped, .spaceLeadChanged,
                 .spaceItemAdded, .spaceItemRemoved, .artifactOpened, .artifactTextLoaded, .connectionsRequested, .googleLoaded:
                reduceWork(action.intent, state: &state)

            case .team(let intent): reduceTeam(intent, state: &state)

            case .conversation(let intent): reduceConversation(intent, state: &state)

            case .task(let intent): reduceTask(intent, state: &state)

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

            case .destinationSelected(let destination):
                guard destination != state.destination else { return }
                state.destination = destination
                open(Self.defaultPage(for: destination, snapshot: state.snapshot), state: &state)

            case .pageSelected(let page):
                open(page, state: &state)

            case .sidebarToggled, .inspectorToggled, .paletteToggled, .spaceTabSelected, .employeeTabSelected, .workLayoutSelected:
                reduceLayout(action.intent, state: &state)

            case .refreshTapped:
                loadStatus(state)
                loadMemory(state)

            case .statusLoaded(let scope, let snapshot):
                guard scope.businessID == state.businessID else { return }
                state.statuses[scope.employeeID] = snapshot
                if scope == state.operationsScope { state.status = .loaded(snapshot) }
                settleAwaiting(&state)

            case .presenceTapped(let employeeID):
                // Needs-you opens the decisions; anyone else opens their DM.
                let needsYou = state.presence.contains { item in
                    if item.id == employeeID, case .needsYou = item.signal { true } else { false }
                }
                open(needsYou ? .approvals : .direct(employeeID), state: &state)

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

            case .preferencesToggled(let open):
                state.preferences = open ? Spawn(Preferences.State()) : nil
                // A business created in Settings joins the rail when Settings closes.
                if !open { loadAccount() }

            case .micTapped, .conversationToggled, .speechEvent, .speechFinished, .speechFailed, .speakingFinished,
                 .stopSpeakingTapped, .voiceErrorDismissed:
                reduceVoice(action.intent, state: &state)
            }
        }
        .ifLet(\.preferences) {
            Preferences()
        }
        .onMount { state in
            #if DEBUG
                Self.applyQAPage(to: &state)
            #endif
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
    func loadFailed(_ error: DevysHTTPError, memory: Bool, state: inout State) {
        if error == .unauthorized {
            let session = session
            store.addTask { await session.expire() }
            return
        }
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

    /// Opens a page; a DM or space opens its conversation, and the right panel follows the page.
    func open(_ page: Page, state: inout State) {
        if case .space = page, page != state.page { state.spaceTab = .conversation }
        if !state.destination.lists(page) { state.destination = page.destination }
        if page != state.page { state.panel = nil }
        state.page = page
        openConversation(for: page, state: &state)
    }

    /// Switches to a business; its team, work and conversations load from the server.
    func select(_ id: String, state: inout State) {
        state.businessID = id
        state.snapshot = WorkspaceSnapshot(business: state.businesses.first { $0.id == id } ?? Business(id: id, name: ""), employees: [])
        state.status = .loading
        state.statuses = [:]
        if state.isConversationMode { endConversation(&state) } else if state.voice.isCapturing { cancelCapture(&state) }
        state.main = nil
        state.panel = nil
        state.summaries = [:]
        state.team.hiring = nil
        state.newTask = nil
        state.google = nil
        state.memory = .loading
        state.access = .loading
        state.accessEmployeeID = nil
        state.models.usage = [:]
        state.models.errors = [:]
        state.work = .loading
        state.decisions = .loading
        state.spaces = .loading
        state.artifacts = []
        state.artifactTexts = [:]
        state.repliesToSpeak = []
        state.page = .today
        state.destination = .home
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

    /// Operations first, whose failures show; then everyone else, whose presence derives from it.
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
