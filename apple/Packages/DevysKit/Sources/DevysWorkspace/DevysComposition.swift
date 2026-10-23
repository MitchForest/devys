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

    #if DEBUG
        /// QA: `DEVYS_SETTINGS=<section>` opens Settings at launch. `DEVYS_SESSION=memory` starts
        /// signed out with nothing kept, and `DEVYS_LOCAL_SERVER` with `DEVYS_LOCAL_KEY` signs in
        /// as a development server's owner (`OwnerFile`), so screenshots need no UI scripting.
        public static var opensSettingsAtLaunch: Bool {
            ProcessInfo.processInfo.environment["DEVYS_SETTINGS"] != nil
        }
    #endif
}
