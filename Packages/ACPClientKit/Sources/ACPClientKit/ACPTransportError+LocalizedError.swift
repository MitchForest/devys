import Foundation

extension ACPTransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidMessageFraming:
            return "The adapter sent invalid message framing."
        case .invalidMessage(let message):
            return "The adapter sent an invalid message: \(message)"
        case .processSpawnFailed(let reason):
            return "The adapter process could not be launched: \(reason)"
        case .processTerminated(let termination):
            let reason = termination.reason.rawValue
            if let exitCode = termination.exitCode {
                return "The adapter process terminated (\(reason), exit \(exitCode))."
            }
            return "The adapter process terminated (\(reason))."
        case .connectionClosed:
            return "The adapter connection closed before the request completed."
        }
    }
}
