import ACPClientKit
import ComposableArchitecture
import Foundation
import Split
import Workspace

public extension WindowFeature {
    struct AgentSessionLaunchIntent: Equatable, Sendable {
        public var workspaceID: Workspace.ID
        public var initialAttachments: [AgentAttachment]
        public var preferredPaneID: PaneID?
        public var preferredKind: ACPAgentKind?

        public init(
            workspaceID: Workspace.ID,
            initialAttachments: [AgentAttachment] = [],
            preferredPaneID: PaneID? = nil,
            preferredKind: ACPAgentKind? = nil
        ) {
            self.workspaceID = workspaceID
            self.initialAttachments = initialAttachments
            self.preferredPaneID = preferredPaneID
            self.preferredKind = preferredKind
        }
    }

    struct AgentSessionLaunchRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var workspaceID: Workspace.ID
        public var kind: ACPAgentKind
        public var initialAttachments: [AgentAttachment]
        public var preferredPaneID: PaneID?

        public init(
            workspaceID: Workspace.ID,
            kind: ACPAgentKind,
            initialAttachments: [AgentAttachment] = [],
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

    enum AgentSessionLaunchResolution: Equatable, Sendable {
        case request(AgentSessionLaunchRequest)
        case presentation(AgentLaunchPresentation)
    }
}

extension WindowFeature {
    func reduceAgentSessionLaunchAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestAgentSessionLaunch(let intent):
            if let preferredKind = intent.preferredKind {
                state.agentSessionLaunchRequest = AgentSessionLaunchRequest(
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
                let resolution = resolveAgentSessionLaunchResolution(
                    intent: intent,
                    defaultHarness: settings.agent.defaultHarness,
                    requestID: requestID
                )
                await send(.agentSessionLaunchResolved(resolution))
            }

        case .agentSessionLaunchResolved(let resolution):
            switch resolution {
            case .request(let request):
                state.agentSessionLaunchRequest = request
            case .presentation(let presentation):
                state.agentLaunchPresentation = presentation
            }
            return .none

        case .setAgentSessionLaunchRequest(let request):
            state.agentSessionLaunchRequest = request
            return .none

        default:
            return .none
        }
    }
}

private func resolveAgentSessionLaunchResolution(
    intent: WindowFeature.AgentSessionLaunchIntent,
    defaultHarness: String?,
    requestID: UUID
) -> WindowFeature.AgentSessionLaunchResolution {
    if let kind = defaultHarness.flatMap(preferredAgentKind(forDefaultHarness:)) {
        return .request(
            WindowFeature.AgentSessionLaunchRequest(
                workspaceID: intent.workspaceID,
                kind: kind,
                initialAttachments: intent.initialAttachments,
                preferredPaneID: intent.preferredPaneID,
                id: requestID
            )
        )
    }

    return .presentation(
        AgentLaunchPresentation(
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
    case AgentSettings.Harness.codex.rawValue:
        .codex
    case AgentSettings.Harness.claudeCode.rawValue:
        .claude
    default:
        nil
    }
}
