import AppKit
import ComposableArchitecture
import Foundation

struct AlertRequest: Equatable, Sendable {
    var title: String
    var message: String?
    var confirmTitle: String
    var cancelTitle: String
    var secondaryTitle: String?

    init(
        title: String,
        message: String? = nil,
        confirmTitle: String,
        cancelTitle: String = "Cancel",
        secondaryTitle: String? = nil
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.secondaryTitle = secondaryTitle
    }
}

enum AlertResponse: Equatable, Sendable {
    case confirm
    case secondary
    case cancel
}

struct AlertClient: Sendable {
    var confirm: @Sendable (AlertRequest) async -> Bool
    var choose: @Sendable (AlertRequest) async -> AlertResponse
    var confirmNow: @MainActor @Sendable (AlertRequest) -> Bool
    var chooseNow: @MainActor @Sendable (AlertRequest) -> AlertResponse

    init(confirm: @escaping @Sendable (AlertRequest) async -> Bool) {
        self.confirm = confirm
        self.choose = { request in
            await confirm(request) ? .confirm : .cancel
        }
        self.confirmNow = { _ in false }
        self.chooseNow = { _ in .cancel }
    }

    init(
        confirm: @escaping @Sendable (AlertRequest) async -> Bool,
        choose: @escaping @Sendable (AlertRequest) async -> AlertResponse,
        confirmNow: @escaping @MainActor @Sendable (AlertRequest) -> Bool = { _ in false },
        chooseNow: @escaping @MainActor @Sendable (AlertRequest) -> AlertResponse = { _ in .cancel }
    ) {
        self.confirm = confirm
        self.choose = choose
        self.confirmNow = confirmNow
        self.chooseNow = chooseNow
    }
}

private enum AlertClientKey: DependencyKey {
    static let liveValue = AlertClient.liveValue
}

extension AlertClient {
    static let liveValue = AlertClient(
        confirm: { request in
            await MainActor.run {
                runConfirmationAlert(request)
            }
        },
        choose: { request in
            await MainActor.run {
                runChoiceAlert(request)
            }
        },
        confirmNow: { request in
            runConfirmationAlert(request)
        },
        chooseNow: { request in
            runChoiceAlert(request)
        }
    )

    @MainActor
    private static func runConfirmationAlert(_ request: AlertRequest) -> Bool {
        runChoiceAlert(request) == .confirm
    }

    @MainActor
    private static func runChoiceAlert(_ request: AlertRequest) -> AlertResponse {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = request.title
        if let message = request.message {
            alert.informativeText = message
        }
        alert.addButton(withTitle: request.confirmTitle)
        if let secondaryTitle = request.secondaryTitle {
            alert.addButton(withTitle: secondaryTitle)
        }
        alert.addButton(withTitle: request.cancelTitle)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .confirm
        case .alertSecondButtonReturn where request.secondaryTitle != nil:
            return .secondary
        default:
            return .cancel
        }
    }
}

extension DependencyValues {
    var alertClient: AlertClient {
        get { self[AlertClientKey.self] }
        set { self[AlertClientKey.self] = newValue }
    }
}
