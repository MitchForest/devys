import Foundation
import TerminalComposer

enum TerminalAgentActivity: Equatable, Sendable {
    case waiting
    case working
    case exited
    case error
}

struct TerminalAgentContext: Equatable, Sendable {
    var match: TerminalAgentMatch?
    var activity: TerminalAgentActivity

    init(
        match: TerminalAgentMatch? = nil,
        activity: TerminalAgentActivity = .waiting
    ) {
        self.match = match
        self.activity = activity
    }

    var serializationStyle: TerminalComposerSerializationStyle {
        match?.serializationStyle ?? .shell
    }

    var windowStatus: TerminalWindowAgentStatus? {
        guard let match else { return nil }
        return TerminalWindowAgentStatus(
            agentName: match.displayName,
            activity: activity
        )
    }
}

struct TerminalWindowAgentStatus: Equatable, Sendable {
    var agentName: String
    var activity: TerminalAgentActivity
}
