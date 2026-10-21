public import Foundation
#if DEBUG
    import os
#endif

/// The server's JSON (src/app/wire.ts and the contracts it composes): snake_case keys, each
/// type naming its keys in explicit `CodingKeys`, and timestamps in ISO 8601 UTC with
/// milliseconds. Every request and response goes through these two coders.
public enum Wire {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ServerDate.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 timestamp: \(text)")
            }
            return date
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ServerDate.format(date))
        }
        return encoder
    }

    /// Decodes a response; in debug builds a failure logs the key path it failed at.
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder().decode(type, from: data)
        } catch let error as DecodingError {
            #if DEBUG
                Logger(subsystem: "devys", category: "wire").error("Decoding \(String(describing: type), privacy: .public) failed: \(error.keyPathDescription, privacy: .public)")
            #endif
            throw error
        }
    }
}

/// Timestamps as the server writes them: ISO 8601 UTC with milliseconds (`…T12:00:00.000Z`).
public enum ServerDate {
    private static let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public static func parse(_ text: String) -> Date? {
        try? Date(text, strategy: style)
    }

    public static func format(_ date: Date) -> String {
        date.formatted(style)
    }
}

/// A value set the server may grow (a state, a kind, a status): a value this client does not know
/// decodes as `unknown` instead of failing the page it is on.
public protocol WireEnum: RawRepresentable, Decodable, Sendable where RawValue == String {
    static var unknown: Self { get }
}

extension WireEnum {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}

extension DecodingError {
    /// Where decoding failed, as `key.0.key: what went wrong`.
    var keyPathDescription: String {
        let (context, problem): (Context?, String) = switch self {
        case .keyNotFound(let key, let context): (context, "missing \(key.stringValue)")
        case .typeMismatch(let type, let context): (context, "expected \(type)")
        case .valueNotFound(let type, let context): (context, "no \(type)")
        case .dataCorrupted(let context): (context, context.debugDescription)
        @unknown default: (nil, "\(self)")
        }
        let path = context?.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".") ?? ""
        return path.isEmpty ? problem : "\(path): \(problem)"
    }
}
