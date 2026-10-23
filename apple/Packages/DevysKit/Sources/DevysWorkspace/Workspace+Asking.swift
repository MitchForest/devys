import ComposableArchitecture2
import Dependencies
package import DevysClient
import Foundation

// MARK: - What employees ask the owner: spend approvals signed here, take overs

/// The signing sheet: the exact spend, then Face ID or Touch ID.
package struct SigningSheet: Equatable {
    package let approval: SpendApproval
    /// The employee who asked, by name.
    package let employee: String
    /// What unlocks the key here: "Face ID", "Touch ID" or "your password".
    package let biometry: String
    package var isSigning = false
    package var error: String?

    package init(approval: SpendApproval, employee: String, biometry: String) {
        self.approval = approval
        self.employee = employee
        self.biometry = biometry
    }
}

package enum AskingIntent {
    /// Approve on a spend approval: the signing sheet shows what exactly is signed.
    case signTapped(decisionID: String)
    case signConfirmed
    /// Nil when the approval was signed and sent; otherwise why not.
    case signFinished(String?)
    case signDismissed
    /// A take-over request: the owner takes the work over and its live browser opens.
    case takeOverTapped(workItemID: String)
    /// A secret request: the secure entry sheet opens for that name (a card when it asks one).
    case secretTapped(decisionID: String)
    /// The sheet's value goes straight to the vault; it never enters state.
    case secretSubmitted(NewSecret)
    /// Nil when it was added; otherwise why not.
    case secretFinished(String?)
    case secretDismissed
    /// A file request: the file the owner chose goes into the business folder and answers it.
    case fileChosen(decisionID: String, file: ChosenFile)
}

extension Workspace {
    func reduceAsking(_ intent: AskingIntent, state: inout State) {
        switch intent {
        case .signTapped(let decisionID):
            guard let decision = state.decisions.first(where: { $0.id == decisionID }),
                  let approval = SpendApproval(decision, businessID: state.businessID)
            else { return }
            state.signing = SigningSheet(approval: approval, employee: state.employeeName(decision.employeeID), biometry: signing.biometry())
        case .signConfirmed:
            guard var sheet = state.signing, !sheet.isSigning else { return }
            sheet.isSigning = true
            sheet.error = nil
            state.signing = sheet
            let approval = sheet.approval
            let signing = signing
            let runtime = runtime
            store.addTask {
                do {
                    try await signing.approveSpend(approval)
                    try store.send(Action(.asking(.signFinished(nil))))
                } catch {
                    try store.send(Action(.asking(.signFinished(Self.signingMessage(error)))))
                }
                try await reloadWork(runtime, approval.businessID)
            }
        case .signFinished(let error):
            guard let sheet = state.signing else { return }
            if let error {
                state.signing?.isSigning = false
                state.signing?.error = error
            } else {
                state.signing = nil
                if let home = state.home.value { state.home = .loaded(home.answering(sheet.approval.decisionID)) }
            }
        case .signDismissed:
            if state.signing?.isSigning != true { state.signing = nil }
        case .takeOverTapped(let workItemID):
            reducePlace(.threadOpened(workItemID), state: &state)
            reducePlace(.layerOpened(.browser(workID: workItemID)), state: &state)
            changeWork(state, failure: "Couldn't take that work over.") { runtime, businessID in
                try await runtime.setTakeover(businessID, workItemID, true)
            }
        case .secretTapped, .secretSubmitted, .secretFinished, .secretDismissed:
            reduceSecretEntry(intent, state: &state)
        case .fileChosen(let decisionID, let file):
            if let home = state.home.value { state.home = .loaded(home.answering(decisionID)) }
            changeWork(state, failure: "That file wasn't sent.") { runtime, businessID in
                try await runtime.sendFile(businessID, decisionID, file)
            }
        }
    }

    /// The secure entry sheet for an employee's secret request; the value never enters state.
    private func reduceSecretEntry(_ intent: AskingIntent, state: inout State) {
        switch intent {
        case .secretTapped(let decisionID):
            guard let decision = state.decisions.first(where: { $0.id == decisionID }) else { return }
            state.secretEntry = SecretEntrySheet(request: decision)
        case .secretSubmitted(let secret):
            guard var sheet = state.secretEntry, !sheet.isSaving, secret.name == sheet.name else { return }
            sheet.isSaving = true
            sheet.error = nil
            state.secretEntry = sheet
            let businessID = state.businessID
            let runtime = runtime
            store.addTask {
                do {
                    _ = try await runtime.addSecret(businessID, secret)
                    try store.send(Action(.asking(.secretFinished(nil))))
                } catch {
                    try store.send(Action(.asking(.secretFinished(SecretEntrySheet.message(error)))))
                }
                try await reloadWork(runtime, businessID)
            }
        case .secretFinished(let error):
            guard let sheet = state.secretEntry else { return }
            if let error {
                state.secretEntry?.isSaving = false
                state.secretEntry?.error = error
            } else {
                state.secretEntry = nil
                if let id = sheet.requestID, let home = state.home.value { state.home = .loaded(home.answering(id)) }
            }
        case .secretDismissed:
            if state.secretEntry?.isSaving != true { state.secretEntry = nil }
        default:
            return
        }
    }

    /// Makes sure this device has a signing key the server knows, once signed in. It does not
    /// prompt: Face ID or Touch ID asks only when something is signed.
    func enrollKey() {
        let signing = signing
        store.addTask { _ = try? await signing.enroll() }
    }

    static func signingMessage(_ error: any Error) -> String {
        switch error {
        case SigningError.cancelled: "Not signed."
        case SigningError.notAllowed:
            "This device can't sign yet: allow it in Settings › Devices on a device that already approves spending."
        case SigningError.unavailable: "This device can't sign approvals."
        case DevysHTTPError.rejected(403, let message) where !message.isEmpty: message
        case DevysHTTPError.rejected(409, _): "That request was already answered or has expired."
        default: "The approval wasn't sent. Try again."
        }
    }
}
