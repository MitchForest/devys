public import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysSpeechLive
import Foundation

public enum DevysComposition {
    /// The single root store. Live clients come from their `DependencyKey`
    /// live values: the shared session hub over the HTTP API and Keychain.
    /// One microphone engine and one voice for the whole app.
    private static let speechCapture = SpeechCaptureClient.live()
    private static let speechPlayback = SpeechPlaybackClient.live()

    @MainActor
    public static func makeLiveStore() -> StoreOf<DevysApp> {
        withDependencies {
            $0.speechCaptureClient = speechCapture
            $0.speechPlaybackClient = speechPlayback
        } operation: {
            Store(initialState: DevysApp.State()) {
                DevysApp()
            }
        }
    }

    /// The macOS Settings window's store; it shares the live clients.
    @MainActor
    public static func makePreferencesStore() -> StoreOf<Preferences> {
        var state = Preferences.State()
        #if DEBUG
            // QA only: DEVYS_SETTINGS=account|team|businesses|devices|voice|appearance opens that section.
            if let raw = ProcessInfo.processInfo.environment["DEVYS_SETTINGS"],
               let section = PreferencesSection.allCases.first(where: { $0.rawValue.lowercased() == raw }) {
                state.section = section
            }
        #endif
        return withDependencies {
            $0.speechCaptureClient = speechCapture
            $0.speechPlaybackClient = speechPlayback
        } operation: {
            Store(initialState: state) {
                Preferences()
            }
        }
    }

    #if DEBUG
        /// QA only: `DEVYS_ENROLL_SERVER` and `DEVYS_ENROLL_CODE` sign in at launch
        /// through the real enrollment exchange, so screenshots need no UI scripting.
        public static var opensSettingsAtLaunch: Bool {
            ProcessInfo.processInfo.environment["DEVYS_SETTINGS"] != nil
        }

        public static func enrollFromEnvironment() async {
            let environment = ProcessInfo.processInfo.environment
            guard let raw = environment["DEVYS_ENROLL_SERVER"], let server = URL(string: raw),
                  let code = environment["DEVYS_ENROLL_CODE"]
            else { return }
            try? await SessionHub.shared.signIn(server: server, code: code)
        }
    #endif
}
