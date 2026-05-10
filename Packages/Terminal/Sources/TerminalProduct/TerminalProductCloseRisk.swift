import Foundation
import TerminalHost

public enum TerminalProductCloseRisk: Equatable, Sendable {
    case knownAgent(displayName: String, process: TerminalForegroundProcess)
    case foregroundProcess(TerminalForegroundProcess)

    public var process: TerminalForegroundProcess {
        switch self {
        case .knownAgent(_, let process), .foregroundProcess(let process):
            process
        }
    }

    public var displayName: String {
        switch self {
        case .knownAgent(let displayName, _):
            displayName
        case .foregroundProcess(let process):
            process.executableName
        }
    }
}
