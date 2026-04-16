// WorkspaceSidebarMode.swift
// Devys - Canonical content sidebar tabs.

enum WorkspaceSidebarMode: String, CaseIterable, Sendable {
    case files
    case agents
}

extension WorkspaceSidebarMode: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "files", "changes", "ports":
            self = .files
        case "agents":
            self = .agents
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported workspace sidebar mode: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
