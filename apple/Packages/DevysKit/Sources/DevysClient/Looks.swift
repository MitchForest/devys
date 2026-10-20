public import DevysCharacter
public import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How an employee or business appears, stored on the server so every client shows the
/// same: the Face, an emoji on a tile, or a photo. A photo's `version` changes per upload.
public enum Look: Equatable, Hashable, Sendable, Codable {
    case face(AvatarSpec)
    /// `tint` is a `BusinessTile.Tint` raw value.
    case emoji(String, tint: String)
    case photo(version: String)

    private enum Key: String, CodingKey { case kind, palette, shape, seed, emoji, tint, version }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "face":
            self = .face(AvatarSpec(
                palette: try container.decode(AvatarPalette.self, forKey: .palette),
                shape: try container.decode(AvatarShape.self, forKey: .shape),
                seed: try container.decode(Int.self, forKey: .seed)
            ))
        case "emoji":
            self = .emoji(try container.decode(String.self, forKey: .emoji), tint: try container.decode(String.self, forKey: .tint))
        case "photo":
            self = .photo(version: try container.decode(String.self, forKey: .version))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown look")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .face(let spec):
            try container.encode("face", forKey: .kind)
            try container.encode(spec.palette, forKey: .palette)
            try container.encode(spec.shape, forKey: .shape)
            try container.encode(spec.seed, forKey: .seed)
        case .emoji(let emoji, let tint):
            try container.encode("emoji", forKey: .kind)
            try container.encode(emoji, forKey: .emoji)
            try container.encode(tint, forKey: .tint)
        case .photo(let version):
            try container.encode("photo", forKey: .kind)
            try container.encode(version, forKey: .version)
        }
    }
}

/// Whose look: a business, or one employee of a business.
public enum LookTarget: Hashable, Sendable {
    case business(String)
    case employee(business: String, employee: String)

    /// The API path the look lives under.
    public var path: String {
        switch self {
        case .business(let id): "api/businesses/\(id)"
        case .employee(let business, let employee): "api/businesses/\(business)/employees/\(employee)"
        }
    }

    /// Where a downloaded photo is kept for one version of the look.
    public func photoKey(_ version: String) -> String {
        switch self {
        case .business(let id): "business:\(id):\(version)"
        case .employee(_, let employee): "\(employee):\(version)"
        }
    }
}

/// Looks on the server: set a Face or emoji, upload a photo, and fetch a photo to show.
public struct LookClient: Sendable {
    /// nil restores the default look.
    public var set: @Sendable (_ target: LookTarget, _ look: Look?) async throws -> Void
    /// Downscales a photo, uploads it, and the server makes it the look.
    public var importPhoto: @Sendable (_ target: LookTarget, _ image: Data) async throws -> Void
    public var photo: @Sendable (_ target: LookTarget) async -> Data?

    public init(
        set: @escaping @Sendable (LookTarget, Look?) async throws -> Void,
        importPhoto: @escaping @Sendable (LookTarget, Data) async throws -> Void,
        photo: @escaping @Sendable (LookTarget) async -> Data?
    ) {
        self.set = set
        self.importPhoto = importPhoto
        self.photo = photo
    }

    public static func live(_ hub: SessionHub) -> Self {
        Self(
            set: { target, look in try await hub.call { api, session in try await api.setLook(session, path: target.path, look: look) } },
            importPhoto: { target, image in
                guard let jpeg = ImageDownscaler.jpeg(from: image, maxPixel: 512) else { throw LookError.unreadableImage }
                try await hub.call { api, session in try await api.uploadLookPhoto(session, path: target.path, jpeg: jpeg) }
            },
            photo: { target in try? await hub.call { api, session in try await api.lookPhoto(session, path: target.path) } }
        )
    }

    public static let inert = Self(set: { _, _ in }, importPhoto: { _, _ in }, photo: { _ in nil })
}

public enum LookError: Error, Equatable, Sendable {
    case unreadableImage
}

/// Converts any image the platform can read into a bounded JPEG.
public enum ImageDownscaler {
    public static func jpeg(from data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel
              ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// The owner's profile photo on the server.
public struct ProfileClient: Sendable {
    public var photo: @Sendable () async throws -> Data?
    public var upload: @Sendable (_ image: Data) async throws -> Void
    public var remove: @Sendable () async throws -> Void

    public init(
        photo: @escaping @Sendable () async throws -> Data?,
        upload: @escaping @Sendable (Data) async throws -> Void,
        remove: @escaping @Sendable () async throws -> Void
    ) {
        self.photo = photo
        self.upload = upload
        self.remove = remove
    }

    public static func live(_ hub: SessionHub) -> Self {
        Self(
            photo: { try await hub.call { api, session in try await api.profilePhoto(session) } },
            upload: { image in
                guard let jpeg = ImageDownscaler.jpeg(from: image, maxPixel: 1024) else { throw LookError.unreadableImage }
                try await hub.call { api, session in try await api.uploadProfilePhoto(session, jpeg: jpeg) }
            },
            remove: { try await hub.call { api, session in try await api.removeProfilePhoto(session) } }
        )
    }

    public static let inert = Self(photo: { nil }, upload: { _ in }, remove: {})
}
