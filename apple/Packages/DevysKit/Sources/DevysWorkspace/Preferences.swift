public import ComposableArchitecture2
import Dependencies
package import DevysCharacter
package import DevysClient
package import Foundation

package enum PreferencesSection: String, CaseIterable, Hashable, Sendable {
    case account = "Account"
    case apps = "Apps"
    case team = "Team"
    case businesses = "Businesses"
    case devices = "Devices"
    case voice = "Voice"
    case appearance = "Appearance"

    package var symbol: String {
        switch self {
        case .account: "person.crop.circle"
        case .team: "person.2"
        case .businesses: "building.2"
        case .apps: "square.grid.2x2"
        case .devices: "laptopcomputer.and.iphone"
        case .voice: "waveform"
        case .appearance: "circle.lefthalf.filled"
        }
    }
}

/// Settings: the owner's name and photo, their businesses and teams, how employees and
/// businesses look, each business's apps and connections, voice and appearance. Businesses, teams, looks and the profile
/// photo are on the server, so every client shows the same.
@Feature
public struct Preferences {
    public init() {}

    public struct State {
        package var section: PreferencesSection = .account
        package var businesses: [Business] = []
        package var teams: [String: [Employee]] = [:]
        package var selectedEmployeeID: String?
        package var selectedBusinessID: String?
        /// Downloaded look photos, by `LookTarget.photoKey`.
        package var lookPhotos: [String: Data] = [:]
        package var ownerName: String?
        package var ownerPhoto: Data?
        package var isUploading = false
        package var voices: [SpeechVoice] = []
        package var voiceSettings = VoiceSettings()
        package var errorText: String?
        /// The business being set up in the New business sheet.
        package var newBusiness: NewBusinessDraft?
        /// The person's signed-in devices, loaded when Devices opens.
        package var devices: Loadable<[Device]> = .loading
        /// Their devices' signing keys: which approve spending, and which wait to be allowed.
        package var keys: [DeviceKey] = []
        package var ownerID: String?
        /// A code for adding a device, shown as a QR code until it expires.
        package var deviceCode: DeviceCode?
        package var isIssuingCode = false
        /// The selected business's app directory and its Google Drive connection, loaded when Apps opens.
        package var apps: Loadable<[AppEntry]> = .loading
        package var google: Loadable<GoogleConnection>?

        public init() {}

        package var allEmployees: [Employee] {
            businesses.flatMap { teams[$0.id] ?? [] }
        }

        /// Where an employee's look lives: under the business whose team lists it.
        package func target(forEmployee id: String) -> LookTarget? {
            businesses.first { (teams[$0.id] ?? []).contains { $0.id == id } }.map { .employee(business: $0.id, employee: id) }
        }
    }

    public struct Action {
        package let intent: Intent

        package init(_ intent: Intent) {
            self.intent = intent
        }
    }

    package enum Intent {
        case sectionSelected(PreferencesSection)
        case employeeSelected(String)
        case businessSelected(String)
        case lookSet(LookTarget, Look?)
        case photoPicked(LookTarget, Data)
        case ownerPhotoPicked(Data)
        case ownerPhotoRemoved
        case ownerRenamed(String)
        case ownerNameSaved(String)
        case lookPhotosLoaded([String: Data])
        case ownerLoaded(name: String?, photo: Data?)
        case voicesLoaded([SpeechVoice])
        case directoryLoaded(Account, teams: [String: [Employee]])
        case business(BusinessIntent)
        case device(DeviceIntent)
        case app(AppIntent)
        case uploadFinished(Data?)
        case failed(String)
        case signOutTapped
        case voiceSettingsChanged(VoiceSettings)
        case previewVoiceTapped
    }

    /// Declared here (not by the macro) so effect helpers can live in their own files.
    @FeatureBindable var store = FeatureStore<Self.State, Self.Action>()

    @Dependency(\.lookClient) private var lookClient: LookClient
    @Dependency(\.profileClient) private var profileClient: ProfileClient
    @Dependency(\.runtimeClient) var runtime: RuntimeClient
    @Dependency(\.signingClient) var signing: SigningClient
    @Dependency(\.sessionClient) private var session: SessionClient
    @Dependency(\.speechPlaybackClient) private var playback: SpeechPlaybackClient
    @Dependency(\.voiceSettingsClient) private var voiceSettingsClient: VoiceSettingsClient

    public var body: some Feature {
        Update { state, action in
            switch action.intent {
            case .sectionSelected(let section):
                state.section = section

            case .employeeSelected(let id):
                state.selectedEmployeeID = id

            case .businessSelected(let id):
                guard id != state.selectedBusinessID else { return }
                state.selectedBusinessID = id
                state.apps = .loading
                state.google = nil

            case .lookSet(let target, let look):
                // Shows at once; the server copy replaces it when the directory reloads.
                switch target {
                case .business(let id):
                    if let index = state.businesses.firstIndex(where: { $0.id == id }) { state.businesses[index].look = look }
                case .employee(let business, let employee):
                    if let index = state.teams[business]?.firstIndex(where: { $0.id == employee }) { state.teams[business]?[index].look = look }
                }
                let client = lookClient
                let runtime = runtime
                store.addTask {
                    do {
                        try await client.set(target, look)
                    } catch {
                        try store.send(Action(.failed("That look couldn't be saved. Try again.")))
                    }
                    try await loadDirectory(runtime)
                }

            case .photoPicked(let target, let data):
                let client = lookClient
                let runtime = runtime
                store.addTask {
                    do {
                        try await client.importPhoto(target, data)
                    } catch {
                        try store.send(Action(.failed("That image couldn't be read. Try a JPEG, PNG or HEIC.")))
                    }
                    try await loadDirectory(runtime)
                }

            case .ownerPhotoPicked(let data):
                state.isUploading = true
                state.errorText = nil
                let profile = profileClient
                store.addTask {
                    do {
                        try await profile.upload(data)
                        try store.send(Action(.uploadFinished(try await profile.photo())))
                    } catch {
                        try store.send(Action(.failed("The photo couldn't be uploaded. Check the connection and try again.")))
                    }
                }

            case .ownerPhotoRemoved:
                state.isUploading = true
                let profile = profileClient
                store.addTask {
                    do {
                        try await profile.remove()
                        try store.send(Action(.uploadFinished(nil)))
                    } catch {
                        try store.send(Action(.failed("The photo couldn't be removed. Try again.")))
                    }
                }

            case .ownerRenamed(let name):
                let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard name != state.ownerName else { return }
                guard !name.isEmpty, name.count <= 80 else {
                    state.errorText = "Your name needs 1 to 80 characters."
                    return
                }
                state.errorText = nil
                let runtime = runtime
                store.addTask {
                    do {
                        try store.send(Action(.ownerNameSaved(try await runtime.rename(name).person.displayName)))
                    } catch {
                        try store.send(Action(.failed("Your name couldn't be saved. Try again.")))
                    }
                }

            case .ownerNameSaved(let name):
                state.ownerName = name

            case .lookPhotosLoaded(let photos):
                state.lookPhotos.merge(photos) { _, new in new }

            case .voicesLoaded(let voices):
                state.voices = voices

            case .ownerLoaded(let name, let photo):
                if let name { state.ownerName = name }
                state.ownerPhoto = photo

            case .directoryLoaded(let account, let teams):
                state.ownerName = account.person.displayName
                state.ownerID = account.person.id
                state.businesses = account.businesses
                state.teams = teams
                if state.selectedBusinessID == nil { state.selectedBusinessID = account.businesses.first?.id }
                if state.selectedEmployeeID == nil { state.selectedEmployeeID = state.allEmployees.first?.id }
                loadLookPhotos(state)

            case .business(let intent):
                reduceBusiness(intent, state: &state)

            case .device(let intent):
                reduceDevice(intent, state: &state)

            case .app(let intent):
                reduceApps(intent, state: &state)

            case .uploadFinished(let photo):
                state.isUploading = false
                state.ownerPhoto = photo

            case .failed(let message):
                state.isUploading = false
                state.errorText = message

            case .signOutTapped:
                let session = session
                store.addTask { await session.signOut() }

            case .voiceSettingsChanged(let settings):
                state.voiceSettings = settings
                voiceSettingsClient.save(settings)

            case .previewVoiceTapped:
                let playback = playback
                let settings = state.voiceSettings
                store.addTask {
                    await playback.stop()
                    try? await playback.speak("Hi, I'm Operations. Two things need you today.", settings.voiceID, settings.rate)
                }
            }
        }
        .onMount { state in
            // Off the main thread: listing system voices waits on the speech service, which can
            // stall for seconds (or indefinitely in a simulator) and froze Settings as it opened.
            let playback = playback
            store.addTask {
                let voices = await Task.detached { playback.voices() }.value
                try store.send(Action(.voicesLoaded(voices)))
            }
            state.voiceSettings = voiceSettingsClient.load()
            let profile = profileClient
            let runtime = runtime
            store.addTask { try? await loadDirectory(runtime) }
            store.addTask {
                let photo = try? await profile.photo()
                try store.send(Action(.ownerLoaded(name: nil, photo: photo.flatMap { $0 })))
            }
        }
    }
}

extension Preferences {
    /// Businesses and each business's team, from the server.
    func loadDirectory(_ runtime: RuntimeClient) async throws {
        let account = try await runtime.account()
        var teams: [String: [Employee]] = [:]
        for business in account.businesses { teams[business.id] = try await runtime.business(business.id).employees }
        try store.send(Action(.directoryLoaded(account, teams: teams)))
    }

    /// Downloads photos for photo looks not yet on hand.
    private func loadLookPhotos(_ state: State) {
        let targets = state.businesses.map { (LookTarget.business($0.id), $0.look) }
            + state.businesses.flatMap { business in
                (state.teams[business.id] ?? []).map { (LookTarget.employee(business: business.id, employee: $0.id), $0.look) }
            }
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
}

extension Preferences.Action {
    package static func sectionSelected(_ section: PreferencesSection) -> Self { Self(.sectionSelected(section)) }
    package static func employeeSelected(_ id: String) -> Self { Self(.employeeSelected(id)) }
    package static func businessSelected(_ id: String) -> Self { Self(.businessSelected(id)) }
    package static func lookSet(_ target: LookTarget, _ look: Look?) -> Self { Self(.lookSet(target, look)) }
    package static func photoPicked(_ target: LookTarget, _ data: Data) -> Self { Self(.photoPicked(target, data)) }
    package static func ownerPhotoPicked(_ data: Data) -> Self { Self(.ownerPhotoPicked(data)) }
    package static var ownerPhotoRemoved: Self { Self(.ownerPhotoRemoved) }
    package static func ownerRenamed(_ name: String) -> Self { Self(.ownerRenamed(name)) }
    package static var signOutTapped: Self { Self(.signOutTapped) }
    package static func voiceSettingsChanged(_ settings: VoiceSettings) -> Self { Self(.voiceSettingsChanged(settings)) }
    package static var previewVoiceTapped: Self { Self(.previewVoiceTapped) }
    package static var newBusinessTapped: Self { Self(.business(.newTapped)) }
    package static func newBusinessEdited(_ draft: NewBusinessDraft) -> Self { Self(.business(.edited(draft))) }
    package static var createBusinessTapped: Self { Self(.business(.createTapped)) }
    package static var newBusinessCancelled: Self { Self(.business(.cancelled)) }
    package static func businessSaved(_ id: String, name: String, brief: String) -> Self { Self(.business(.saveTapped(id: id, name: name, brief: brief))) }
    package static var devicesRequested: Self { Self(.device(.requested)) }
    package static func deviceRevoked(_ id: String) -> Self { Self(.device(.revokeTapped(id))) }
    package static func keyAllowed(_ id: String) -> Self { Self(.device(.allowTapped(keyID: id))) }
    package static var addDeviceTapped: Self { Self(.device(.addTapped)) }
    package static var deviceCodeDismissed: Self { Self(.device(.codeDismissed)) }
    package static var appsRequested: Self { Self(.app(.requested)) }
    package static func appInstallToggled(_ id: String, _ install: Bool) -> Self { Self(.app(.installToggled(appID: id, install))) }
    package static func appPinToggled(_ id: String, _ pinned: Bool) -> Self { Self(.app(.pinToggled(appID: id, pinned))) }
}
