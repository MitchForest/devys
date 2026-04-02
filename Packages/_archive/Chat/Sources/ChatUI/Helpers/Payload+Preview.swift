import ChatCore

public extension Payload {
    /// A short textual preview of the payload for display in message block cards.
    var chatPreviewText: String? {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .null:
            return nil
        case .array(let values):
            return values.prefix(3).compactMap(\.chatPreviewText)
                .joined(separator: " · ")
        case .object(let object):
            let orderedKeys = object.keys.sorted().prefix(4)
            let rendered = orderedKeys.compactMap { key -> String? in
                guard let value = object[key]?.chatPreviewText else {
                    return nil
                }
                return "\(key): \(value)"
            }
            return rendered.joined(separator: "\n")
        }
    }
}
