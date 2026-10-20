import Foundation

/// How one eye renders.
public enum EyeRender: Equatable, Sendable {
    /// A rounded solid — the everyday eye.
    case fill
    /// A hollow ring (the Ring family's open eye).
    case ring
    /// An upward crescent — joy.
    case arc
    /// An ✕ — it hit a wall.
    case cross
}

/// One eye, in unit face space (0…1 of the face side).
public struct EyePose: Equatable, Sendable {
    public var centerX: Double
    public var centerY: Double
    public var width: Double
    public var height: Double
    /// Corner radius as a fraction of the face side.
    public var cornerRadius: Double
    /// Tilt in radians.
    public var tilt: Double
    public var render: EyeRender

    public init(
        centerX: Double,
        centerY: Double,
        width: Double,
        height: Double,
        cornerRadius: Double,
        tilt: Double,
        render: EyeRender
    ) {
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.tilt = tilt
        self.render = render
    }
}

/// One deterministic frame of the face: everything the renderer draws,
/// in unit coordinates. No colors, no pixels, no SwiftUI.
public struct FacePose: Equatable, Sendable {
    public var eyes: [EyePose]
    /// Paused: a single dim dash where the eyes were.
    public var showsStandbyDash: Bool
    /// 0–3 dots beside the upward gaze while thinking.
    public var thinkingDots: Int
    /// 0–2 z's drifting above the half-lids while asleep.
    public var sleepZeds: Int

    public init(
        eyes: [EyePose] = [],
        showsStandbyDash: Bool = false,
        thinkingDots: Int = 0,
        sleepZeds: Int = 0
    ) {
        self.eyes = eyes
        self.showsStandbyDash = showsStandbyDash
        self.thinkingDots = thinkingDots
        self.sleepZeds = sleepZeds
    }

    public static let standby = FacePose(showsStandbyDash: true)
}

extension FacePose {
    /// The whole face in one pure function: identical inputs produce
    /// identical frames on every client and in tests.
    /// - Parameter motionEnabled: false freezes the gaze wander (Reduce
    ///   Motion) while the blink clock keeps running on real time.
    public static func pose(
        spec: AvatarSpec,
        mood: BotMood,
        time: Double,
        budget: MotionBudget,
        pokePhase: Double? = nil,
        motionEnabled: Bool = true
    ) -> FacePose {
        guard mood != .off else { return .standby }
        let geometry = EyeFamily(shape: spec.shape).geometry
        let temperament = Temperament(seed: spec.seed)
        let motionTime = motionEnabled ? time : Double(spec.seed % 64) * 1.37
        let expression = Expression(mood: mood)

        var render: EyeRender = geometry.isRing ? .ring : .fill
        var heightScale = expression.heightScale
        var widthScale = 1.0
        var gazeX = expression.gazeX
        var gazeY = expression.gazeY

        // Poke: a happy flash with a soft squash bounce, hero sizes only.
        if budget == .full, let pokePhase, pokePhase >= 0, pokePhase < 0.9 {
            render = .arc
            if motionEnabled {
                let spring = exp(-pokePhase * 5) * cos(pokePhase * 22) * 0.1
                widthScale = 1 + spring
                heightScale *= 1 - spring
            }
        } else if expression.render != nil {
            render = expression.render ?? render
        }

        // Idle gaze wander is the proof of an inner life; larger budgets only.
        if budget != .minimal, expression.wanders {
            gazeX = sin(motionTime * temperament.wanderRate * 1.5 + temperament.wanderPhase) * temperament.wanderAmp
            gazeY = cos(motionTime * temperament.wanderRate + temperament.wanderPhase * 2) * temperament.wanderAmp * 0.6
        }

        // Blink rides on top of everything except joy, crosses, and sleep.
        if render == .fill || render == .ring, mood != .asleep {
            heightScale *= 1 - temperament.blinkCloseness(at: time) * 0.9
        }

        let gazeRange = 0.055
        let centerX = 0.5 + gazeX * gazeRange
        let centerY = 0.5 + gazeY * gazeRange + expression.lift * 0.1

        var eyes: [EyePose] = []
        for direction in [-1.0, 1.0] {
            let width = geometry.width * widthScale
            let height = max(geometry.height * heightScale, 0.02)
            // A ring squeezed shut reads as a lid line, not a ring.
            var eyeRender = render
            if eyeRender == .ring && height < geometry.height * 0.5 {
                eyeRender = .fill
            }
            eyes.append(
                EyePose(
                    centerX: centerX + direction * geometry.separation / 2,
                    centerY: centerY + (direction > 0 ? expression.asymmetry * 0.16 : 0),
                    width: width,
                    height: height,
                    cornerRadius: min(width, height) / 2 * geometry.cornerFactor,
                    tilt: geometry.tilt * direction,
                    render: eyeRender
                )
            )
        }

        let dots = mood == .thinking && budget == .full ? Int(motionTime * 2) % 4 : 0
        // Half-lids alone read as a squint at sidebar sizes; the z is the
        // glyph everyone knows. Too small to resolve below 28 pt.
        let zeds = mood == .asleep && budget != .minimal ? 1 + Int(motionTime * 0.8) % 2 : 0
        return FacePose(eyes: eyes, thinkingDots: dots, sleepZeds: zeds)
    }
}

extension FacePose {
    /// The family's calm, open-eyed pose with no clock: no wander, no
    /// blink, no glyphs. Pickers render each option with this so every
    /// family stays visually distinct while only the selected option
    /// moves (docs/product.md, Characters).
    public static func still(spec: AvatarSpec) -> FacePose {
        let geometry = EyeFamily(shape: spec.shape).geometry
        let render: EyeRender = geometry.isRing ? .ring : .fill
        var eyes: [EyePose] = []
        for direction in [-1.0, 1.0] {
            eyes.append(
                EyePose(
                    centerX: 0.5 + direction * geometry.separation / 2,
                    centerY: 0.5,
                    width: geometry.width,
                    height: geometry.height,
                    cornerRadius: min(geometry.width, geometry.height) / 2 * geometry.cornerFactor,
                    tilt: geometry.tilt * direction,
                    render: render
                )
            )
        }
        return FacePose(eyes: eyes)
    }
}

/// The emotional alphabet: how each mood shapes the eyes
/// (docs/character-face.html). Crescents mean joy, slits mean focus, a
/// raised eye means "waiting on you", ✕ means it hit a wall.
private struct Expression {
    var heightScale = 1.0
    var lift = 0.0
    /// Negative raises the right eye — the quizzical eyebrow.
    var asymmetry = 0.0
    var gazeX = 0.0
    var gazeY = 0.0
    var render: EyeRender?
    var wanders = false

    init(mood: BotMood) {
        switch mood {
        case .idle:
            wanders = true
        case .listening:
            heightScale = 1.08
        case .thinking:
            heightScale = 0.72
            gazeX = -0.5
            gazeY = -0.75
        case .working:
            heightScale = 0.34
            gazeY = 0.35
        case .waiting:
            heightScale = 1.06
            asymmetry = -0.16
        case .celebrate:
            render = .arc
        case .oops:
            render = .cross
        case .asleep:
            heightScale = 0.4
            lift = 0.08
        case .off:
            break
        }
    }
}
