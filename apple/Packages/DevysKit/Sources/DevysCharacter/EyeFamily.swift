/// The eight eye families — a face style per silhouette, like choosing a
/// typeface. `AvatarShape` raw values are persisted in local stores and
/// must never be renamed, so the family stays a computed projection
/// (docs/character-face.html).
enum EyeFamily: Equatable, Sendable {
    case capsule
    case round
    case squircle
    case wide
    case tall
    case keen
    case dot
    case ring

    init(shape: AvatarShape) {
        switch shape {
        case .circle: self = .round
        case .roundedSquare: self = .squircle
        case .capsule: self = .capsule
        case .blob: self = .wide
        case .triangle: self = .keen
        case .hexagon: self = .ring
        case .cloud: self = .dot
        case .drop: self = .tall
        }
    }

    /// Base geometry in unit face space (fractions of the face side).
    var geometry: EyeGeometry {
        switch self {
        case .capsule: EyeGeometry(width: 0.16, height: 0.42, cornerFactor: 1.0, separation: 0.36, tilt: 0)
        case .round: EyeGeometry(width: 0.26, height: 0.26, cornerFactor: 1.0, separation: 0.42, tilt: 0)
        case .squircle: EyeGeometry(width: 0.26, height: 0.30, cornerFactor: 0.42, separation: 0.42, tilt: 0)
        case .wide: EyeGeometry(width: 0.30, height: 0.17, cornerFactor: 1.0, separation: 0.44, tilt: 0)
        case .tall: EyeGeometry(width: 0.12, height: 0.48, cornerFactor: 1.0, separation: 0.30, tilt: 0)
        case .keen: EyeGeometry(width: 0.24, height: 0.26, cornerFactor: 0.5, separation: 0.42, tilt: 0.16)
        case .dot: EyeGeometry(width: 0.13, height: 0.13, cornerFactor: 1.0, separation: 0.36, tilt: 0)
        case .ring: EyeGeometry(width: 0.26, height: 0.26, cornerFactor: 1.0, separation: 0.44, tilt: 0, isRing: true)
        }
    }
}

/// One family's base eye shape, all values as fractions of the face side.
struct EyeGeometry: Equatable, Sendable {
    var width: Double
    var height: Double
    /// 1.0 = fully rounded (capsule/circle); lower keeps corners.
    var cornerFactor: Double
    /// Distance between the two eye centers.
    var separation: Double
    /// Outward tilt in radians, mirrored per eye.
    var tilt: Double
    var isRing: Bool

    init(
        width: Double,
        height: Double,
        cornerFactor: Double,
        separation: Double,
        tilt: Double,
        isRing: Bool = false
    ) {
        self.width = width
        self.height = height
        self.cornerFactor = cornerFactor
        self.separation = separation
        self.tilt = tilt
        self.isRing = isRing
    }
}
