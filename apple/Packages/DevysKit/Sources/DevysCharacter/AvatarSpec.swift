/// Procedural Bot avatar recipe. The same spec renders identically at every
/// size on every client as a screen being: palette selects the phosphor
/// tone, shape selects the species, and the seed drives temperament
/// (docs/product.md, The Face). Raw values are persisted in
/// local stores; renaming a case silently wipes them, so never rename.
public struct AvatarSpec: Equatable, Hashable, Sendable, Codable {
    public var palette: AvatarPalette
    public var shape: AvatarShape
    /// Seeds deterministic per-character variation (eye placement/tilt).
    public var seed: Int

    public init(palette: AvatarPalette, shape: AvatarShape, seed: Int) {
        self.palette = palette
        self.shape = shape
        self.seed = seed
    }
}

/// The ten curated avatar colors, in the editor's dot order.
public enum AvatarPalette: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    case brown
    case red
    case orange
    case amber
    case green
    case teal
    case blue
    case purple
    case pink
    case gray
}

/// The eight character silhouettes, in the editor's glyph order.
public enum AvatarShape: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    case circle
    case blob
    case roundedSquare
    case capsule
    case triangle
    case hexagon
    case cloud
    case drop
}
