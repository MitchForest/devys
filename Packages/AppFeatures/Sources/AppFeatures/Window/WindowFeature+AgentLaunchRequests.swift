import ACPClientKit
import ComposableArchitecture
import Foundation
import Split
import Workspace

public extension WindowFeature {
    struct ChatSessionLaunchIntent: Equatable, Sendable {
        public var workspaceID: Workspace.ID
        public var initialAttachments: [ChatAttachment]
        public var preferredPaneID: PaneID?
        public var preferredKind: ACPAgentKind?

        public init(
            workspaceID: Workspace.ID,
            initialAttachments: [ChatAttachment] = [],
            preferredPaneID: PaneID? = nil,
            preferredKind: ACPAgentKind? = nil
        ) {
            self.workspaceID = workspaceID
            self.initialAttachments = initialAttachments
            self.preferredPaneID = preferredPaneID
            self.preferredKind = preferredKind
        }
    }

    struct ChatSessionLaunchRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var workspaceID: Workspace.ID
        public var kind: ACPAgentKind
        public var initialAttachments: [ChatAttachment]
        public var preferredPaneID: PaneID?

        public init(
            workspaceID: Workspace.ID,
            kind: ACPAgentKind,
            initialAttachments: [ChatAttachment] = [],
            preferredPaneID: PaneID? = nil,
            id: UUID = UUID()
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.kind = kind
            self.initialAttachments = initialAttachments
            self.preferredPaneID = preferredPaneID
        }
    }

    enum ChatSessionLaunchResolution: Equatable, Sendable {
        case request(ChatSessionLaunchRequest)
        case presentation(ChatLaunchPresentation)
    }
}

extension WindowFeature {
    func reduceAgentSessionLaunchAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestChatSessionLaunch(let intent):
            if let preferredKind = intent.preferredKind {
                state.chatSessionLaunchRequest = ChatSessionLaunchRequest(
                    workspaceID: intent.workspaceID,
                    kind: preferredKind,
                    initialAttachments: intent.initialAttachments,
                    preferredPaneID: intent.preferredPaneID,
                    id: uuid()
                )
                return .none
            }

            let globalSettingsClient = self.globalSettingsClient
            let requestID = uuid()
            return .run { send in
                let settings = await globalSettingsClient.load()
                let resolution = resolveChatSessionLaunchResolution(
                    intent: intent,
                    defaultHarness: settings.chat.defaultHarness,
                    requestID: requestID
                )
                await send(.chatSessionLaunchResolved(resolution))
            }

        case .chatSessionLaunchResolved(let resolution):
            switch resolution {
            case .request(let request):
                state.chatSessionLaunchRequest = request
            case .presentation(let presentation):
                state.chatLaunchPresentation = presentation
            }
            return .none

        case .setChatSessionLaunchRequest(let request):
            state.chatSessionLaunchRequest = request
            return .none

        default:
            return .none
        }
    }
}

private func resolveChatSessionLaunchResolution(
    intent: WindowFeature.ChatSessionLaunchIntent,
    defaultHarness: String?,
    requestID: UUID
) -> WindowFeature.ChatSessionLaunchResolution {
    if let kind = defaultHarness.flatMap(preferredAgentKind(forDefaultHarness:)) {
        return .request(
            WindowFeature.ChatSessionLaunchRequest(
                workspaceID: intent.workspaceID,
                kind: kind,
                initialAttachments: intent.initialAttachments,
                preferredPaneID: intent.preferredPaneID,
                id: requestID
            )
        )
    }

    return .presentation(
        ChatLaunchPresentation(
            workspaceID: intent.workspaceID,
            initialAttachments: intent.initialAttachments,
            preferredPaneID: intent.preferredPaneID,
            pendingSessionID: nil,
            pendingTabID: nil
        )
    )
}

private func preferredAgentKind(
    forDefaultHarness rawValue: String
) -> ACPAgentKind? {
    switch rawValue {
    case ChatSettings.Harness.codex.rawValue:
        .codex
    case ChatSettings.Harness.claudeCode.rawValue:
        .claude
    default:
        nil
    }
}
