import Foundation

public enum ServerJSONCoding {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encodeValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try makeEncoder().encode(value)
        return try makeDecoder().decode(JSONValue.self, from: data)
    }

    public static func decodeValue<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try makeEncoder().encode(value)
        return try makeDecoder().decode(type, from: data)
    }
}
