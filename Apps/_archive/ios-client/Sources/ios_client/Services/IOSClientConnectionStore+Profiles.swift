import Foundation
import ServerProtocol

extension IOSClientConnectionStore {
    func refreshCommandProfiles() {
        guard let baseURL = connectedBaseURL else { return }
        Task {
            do {
                let response = try await client.listCommandProfiles(baseURL: baseURL)
                applyCommandProfiles(response.profiles)
                persistConnectionDraft()
            } catch {
                state = .failed("Refresh command profiles failed: \(error.localizedDescription)")
            }
        }
    }

    func makeNewCommandProfileDraft() -> CommandProfileDraft {
        CommandProfileDraft()
    }

    func makeCommandProfileDraft(for profile: CommandProfile) -> CommandProfileDraft {
        CommandProfileDraft(profile: profile, selectedCommandProfileID: selectedCommandProfileID)
    }

    func clearCommandProfileEditorFeedback() {
        commandProfileEditorMessage = nil
        commandProfileValidationErrors = []
        commandProfileValidationWarnings = []
    }

    func setStartupDefaultCommandProfile(_ profileID: String) {
        guard commandProfiles.contains(where: { $0.id == profileID }) else {
            commandProfileEditorMessage = "Profile \(profileID) was not found."
            return
        }

        selectedCommandProfileID = profileID
        persistConnectionDraft()
        commandProfileEditorMessage = "Startup default set to \(profileID)."
    }

    func validateCommandProfileDraft(_ draft: CommandProfileDraft) {
        guard let baseURL = connectedBaseURL else {
            commandProfileEditorMessage = "Connect before validating profiles."
            return
        }
        guard let profile = parseCommandProfileDraft(
            draft,
            failureMessage: "Validation failed."
        ) else {
            return
        }

        clearCommandProfileEditorFeedback()
        isMutatingCommandProfile = true

        Task {
            await performCommandProfileValidation(baseURL: baseURL, profile: profile)
        }
    }

    func saveCommandProfileDraft(_ draft: CommandProfileDraft, onComplete: ((Bool) -> Void)? = nil) {
        guard let baseURL = connectedBaseURL else {
            commandProfileEditorMessage = "Connect before saving profiles."
            onComplete?(false)
            return
        }
        guard let profile = parseCommandProfileDraft(
            draft,
            failureMessage: "Save blocked by local validation."
        ) else {
            onComplete?(false)
            return
        }

        clearCommandProfileEditorFeedback()
        isMutatingCommandProfile = true

        Task {
            await performCommandProfileSave(
                baseURL: baseURL,
                profile: profile,
                draft: draft,
                onComplete: onComplete
            )
        }
    }

    func deleteCommandProfile(id profileID: String) {
        guard let baseURL = connectedBaseURL else {
            commandProfileEditorMessage = "Connect before deleting profiles."
            return
        }
        if let profile = commandProfiles.first(where: { $0.id == profileID }), profile.isDefault {
            commandProfileEditorMessage = "Default profiles cannot be deleted."
            return
        }

        clearCommandProfileEditorFeedback()
        isMutatingCommandProfile = true

        Task {
            await performCommandProfileDelete(baseURL: baseURL, profileID: profileID)
        }
    }
}

private extension IOSClientConnectionStore {
    func parseCommandProfileDraft(
        _ draft: CommandProfileDraft,
        failureMessage: String
    ) -> CommandProfile? {
        do {
            return try draft.toProfile()
        } catch {
            clearCommandProfileEditorFeedback()
            commandProfileValidationErrors = [error.localizedDescription]
            commandProfileEditorMessage = failureMessage
            return nil
        }
    }

    func performCommandProfileValidation(baseURL: URL, profile: CommandProfile) async {
        defer { isMutatingCommandProfile = false }

        do {
            let validation = try await client.validateCommandProfile(baseURL: baseURL, profile: profile)
            commandProfileValidationErrors = validation.errors
            commandProfileValidationWarnings = validation.warnings
            commandProfileEditorMessage = validation.isValid
                ? "Validation passed."
                : "Validation failed."
        } catch {
            commandProfileValidationErrors = ["Validation request failed: \(error.localizedDescription)"]
            commandProfileValidationWarnings = []
            commandProfileEditorMessage = "Validation request failed."
        }
    }

    func performCommandProfileSave(
        baseURL: URL,
        profile: CommandProfile,
        draft: CommandProfileDraft,
        onComplete: ((Bool) -> Void)?
    ) async {
        defer { isMutatingCommandProfile = false }

        do {
            let validation = try await client.validateCommandProfile(baseURL: baseURL, profile: profile)
            commandProfileValidationErrors = validation.errors
            commandProfileValidationWarnings = validation.warnings
            guard validation.isValid else {
                commandProfileEditorMessage = "Save blocked by server validation."
                onComplete?(false)
                return
            }

            _ = try await client.saveCommandProfile(baseURL: baseURL, profile: profile)
            let response = try await client.listCommandProfiles(baseURL: baseURL)
            applyCommandProfiles(response.profiles)
            applyStartupDefaultAfterProfileSave(draft: draft, profileID: profile.id)
            persistConnectionDraft()

            commandProfileEditorMessage = "Saved profile \(profile.id)."
            onComplete?(true)
        } catch {
            commandProfileValidationErrors = ["Save failed: \(error.localizedDescription)"]
            commandProfileValidationWarnings = []
            commandProfileEditorMessage = "Save failed."
            onComplete?(false)
        }
    }

    func performCommandProfileDelete(baseURL: URL, profileID: String) async {
        defer { isMutatingCommandProfile = false }

        do {
            _ = try await client.deleteCommandProfile(baseURL: baseURL, profileID: profileID)
            let response = try await client.listCommandProfiles(baseURL: baseURL)
            applyCommandProfiles(response.profiles)
            persistConnectionDraft()
            commandProfileEditorMessage = "Deleted profile \(profileID)."
        } catch {
            commandProfileValidationErrors = ["Delete failed: \(error.localizedDescription)"]
            commandProfileValidationWarnings = []
            commandProfileEditorMessage = "Delete failed."
        }
    }

    func applyStartupDefaultAfterProfileSave(draft: CommandProfileDraft, profileID: String) {
        if draft.setAsStartupDefault {
            selectedCommandProfileID = profileID
            return
        }
        if selectedCommandProfileID == profileID {
            selectedCommandProfileID = commandProfiles.first?.id ?? profileID
        }
    }
}
