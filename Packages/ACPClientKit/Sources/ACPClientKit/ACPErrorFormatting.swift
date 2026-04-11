import Foundation

public enum ACPErrorFormatting {
    public static func describe(_ error: any Error) -> String {
        if let error = error as? ACPAdapterLaunchError {
            return error.localizedDescription
        }
        if let error = error as? ACPInitializeFailure {
            return error.localizedDescription
        }
        if let error = error as? ACPTransportError {
            return error.localizedDescription
        }
        if let error = error as? ACPRemoteError {
            return error.localizedDescription
        }
        if let error = error as? DecodingError {
            return describeDecodingError(error)
        }
        if let error = error as? LocalizedError,
           let description = error.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }

    private static func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            let path = codingPathDescription(context.codingPath)
            return "Invalid adapter response at \(path): expected \(type). " +
                context.debugDescription
        case .valueNotFound(let type, let context):
            let path = codingPathDescription(context.codingPath)
            return "Invalid adapter response at \(path): missing \(type). " +
                context.debugDescription
        case .keyNotFound(let key, let context):
            let path = codingPathDescription(context.codingPath + [key])
            return "Invalid adapter response at \(path): \(context.debugDescription)"
        case .dataCorrupted(let context):
            let path = codingPathDescription(context.codingPath)
            return "Invalid adapter response at \(path): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func codingPathDescription(_ codingPath: [any CodingKey]) -> String {
        guard !codingPath.isEmpty else { return "<root>" }

        return codingPath.map { key in
            if let intValue = key.intValue {
                return "[\(intValue)]"
            }
            return key.stringValue
        }
        .joined(separator: ".")
        .replacingOccurrences(of: ".[", with: "[")
    }
}
