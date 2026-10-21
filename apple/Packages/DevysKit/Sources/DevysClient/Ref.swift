import Foundation

/// A record's address, `devys:<app>/<kind>/<id>` with the id percent-encoded exactly as
/// JavaScript's `encodeURIComponent` does (src/protocol/ref.ts). The kinds this client opens are
/// named cases, by the app that owns each (a file's id is its absolute path); a well-formed ref of
/// any other app or kind is `unknown`, kept and shown, never opened.
public enum Ref: Hashable, Sendable, CustomStringConvertible {
    case artifact(String)
    case file(String)
    case codeSession(String)
    case workItem(String)
    case workProject(String)
    /// A record kind the server knows and this client does not yet.
    case unknown(app: String, kind: String, id: String)

    /// The app that owns the record.
    public var app: String {
        switch self {
        case .artifact, .file: "documents"
        case .codeSession: "code"
        case .workItem, .workProject: "work"
        case .unknown(let app, _, _): app
        }
    }

    /// The record's kind within its app.
    public var kind: String {
        switch self {
        case .artifact: "artifact"
        case .file: "file"
        case .codeSession: "session"
        case .workItem: "item"
        case .workProject: "project"
        case .unknown(_, let kind, _): kind
        }
    }

    /// `<app>/<kind>`: what a client's layer registry is keyed by.
    public var recordKind: String { "\(app)/\(kind)" }

    /// The record's (decoded) id.
    public var id: String {
        switch self {
        case .artifact(let id), .file(let id), .codeSession(let id), .workItem(let id), .workProject(let id), .unknown(_, _, let id): id
        }
    }

    public var description: String { "devys:\(app)/\(kind)/\(Self.encode(id))" }

    /// The ref this string names (`unknown` for an app or kind this client does not know), or nil
    /// for anything that is not a ref: an empty part, or an id not in the encoding `description` gives it.
    public init?(_ value: String) {
        guard value.hasPrefix("devys:") else { return nil }
        let parts = value.dropFirst("devys:".count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        let lowercase = { (part: Substring) in part.unicodeScalars.allSatisfy { ("a"..."z").contains($0) } }
        guard lowercase(parts[0]), lowercase(parts[1]) else { return nil }
        let encoded = String(parts[2])
        guard let id = Self.decode(encoded), Self.encode(id) == encoded else { return nil }
        switch (parts[0], parts[1]) {
        case ("documents", "artifact"): self = .artifact(id)
        case ("documents", "file"): self = .file(id)
        case ("code", "session"): self = .codeSession(id)
        case ("work", "item"): self = .workItem(id)
        case ("work", "project"): self = .workProject(id)
        default: self = .unknown(app: String(parts[0]), kind: String(parts[1]), id: id)
        }
    }

    /// The bytes `encodeURIComponent` leaves as they are.
    private static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()".utf8)

    static func encode(_ id: String) -> String {
        var out = ""
        for byte in id.utf8 {
            if unreserved.contains(byte) {
                out.append(Character(Unicode.Scalar(byte)))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    /// `decodeURIComponent`: nil for a malformed escape or bytes that are not UTF-8.
    static func decode(_ encoded: String) -> String? {
        var bytes: [UInt8] = []
        var iterator = Array(encoded.utf8).makeIterator()
        while let byte = iterator.next() {
            guard byte == UInt8(ascii: "%") else {
                bytes.append(byte)
                continue
            }
            guard let high = iterator.next().flatMap(hexValue), let low = iterator.next().flatMap(hexValue) else { return nil }
            bytes.append(high << 4 | low)
        }
        return String(validating: bytes, as: UTF8.self)
    }

    private static func hexValue(_ digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): digit - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}

extension Ref: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let ref = Ref(value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a ref: \(value)")
        }
        self = ref
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
