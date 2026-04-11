import Foundation

public typealias ACPObject = [String: ACPValue]

public enum ACPValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case string(String)
    case integer(Int)
    case double(Double)
    case array([ACPValue])
    case object(ACPObject)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ACPValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode(ACPObject.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    public var objectValue: ACPObject? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [ACPValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var integerValue: Int? {
        switch self {
        case .integer(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .integer(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public subscript(key: String) -> ACPValue? {
        objectValue?[key]
    }

    public static func encode<EncodableValue: Encodable>(_ value: EncodableValue) throws -> ACPValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(ACPValue.self, from: data)
    }

    public static func decode<DecodableValue: Decodable>(
        _ type: DecodableValue.Type,
        from value: ACPValue?
    ) throws -> DecodableValue {
        let encodedValue = value ?? .null
        let data = try JSONEncoder().encode(encodedValue)
        return try JSONDecoder().decode(type, from: data)
    }
}
