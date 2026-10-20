import Foundation
public import DevysCharacter
public import SwiftUI

/// Renders an `AvatarSpec` as its face: two large morphing eyes on an
/// adaptive tile — a computer that shows human emotion
/// (docs/product.md, Characters). Shape selects the eye
/// family, palette the eye color, seed the temperament. Mood changes
/// blink-morph: the eyes close as one expression and open as the next.
public struct DevysAvatar: View {
    private let spec: AvatarSpec
    private let size: CGFloat
    private let mood: BotMood
    private let label: String?
    private let reactAt: Date?
    private let showsTile: Bool
    private let isAnimated: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var pokedAt: Date?
    @State private var previousMood: BotMood?
    @State private var moodChangedAt: Date?

    /// - Parameters:
    ///   - mood: presentation state projected by the caller; never
    ///     persisted.
    ///   - label: a Bot name makes the avatar announce "name, state";
    ///     nil keeps it decorative and hidden from accessibility.
    ///   - reactAt: an external delight trigger — the face flashes its
    ///     happy crescents when this date changes, e.g. when the editor's
    ///     color or family selection changes.
    ///   - showsTile: false drops the coin for hero moments where the
    ///     face lives directly on the surface.
    ///   - isAnimated: false renders the family's calm, open-eyed still
    ///     pose with no clock at all — pickers use it so unselected
    ///     options stay quiet and never share one expression.
    public init(
        _ spec: AvatarSpec,
        size: CGFloat,
        mood: BotMood = .idle,
        label: String? = nil,
        reactAt: Date? = nil,
        showsTile: Bool = true,
        isAnimated: Bool = true
    ) {
        self.spec = spec
        self.size = size
        self.mood = mood
        self.label = label
        self.reactAt = reactAt
        self.showsTile = showsTile
        self.isAnimated = isAnimated
    }

    public var body: some View {
        let core = Group {
            if isAnimated {
                TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
                    Canvas { context, canvasSize in
                        draw(context: context, canvasSize: canvasSize, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            } else {
                Canvas { context, canvasSize in
                    drawStill(context: context, canvasSize: canvasSize)
                }
            }
        }
        .frame(width: size, height: size)
        .onChange(of: mood) { oldMood, _ in
            previousMood = oldMood
            moodChangedAt = Date()
        }
        .accessibilityHidden(label == nil)
        .accessibilityLabel(Text(accessibilitySummary))
        return Group {
            if budget == .full, isAnimated {
                core.onTapGesture { pokedAt = Date() }
            } else {
                core
            }
        }
    }

    private var budget: MotionBudget { MotionBudget(size: size) }

    private var frameInterval: Double {
        switch budget {
        case .full: 1 / 30
        case .poses: 1 / 10
        case .minimal: 1 / 4
        }
    }

    private var accessibilitySummary: String {
        guard let label else { return "" }
        return "\(label), \(mood.accessibilityDescription)"
    }

    /// The most recent poke, whether from a tap or the caller's trigger.
    private var pokeStart: Date? {
        switch (pokedAt, reactAt) {
        case (nil, nil): nil
        case (let poked?, nil): poked
        case (nil, let react?): react
        case (let poked?, let react?): max(poked, react)
        }
    }

    private func draw(context: GraphicsContext, canvasSize: CGSize, time: Double) {
        let side = min(canvasSize.width, canvasSize.height)
        let light = colorScheme != .dark
        let rgb = light ? spec.palette.eyeInk : spec.palette.eyeGlow
        let eyeColor = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)

        if showsTile {
            drawTile(context: context, side: side, light: light, eyeColor: eyeColor)
        }

        // Blink-morph between moods: the old expression closes, the new
        // one opens — half a blink each way.
        let transition = moodChangedAt.map { time - $0.timeIntervalSinceReferenceDate }
        var poseMood = mood
        var morphScale = 1.0
        if let transition, let previousMood, transition >= 0, transition < 0.32, !reduceMotion {
            let phase = transition / 0.32
            if phase < 0.5 {
                poseMood = previousMood
                morphScale = 1 - phase * 2
            } else {
                morphScale = phase * 2 - 1
            }
        }

        let pokePhase = pokeStart.map { time - $0.timeIntervalSinceReferenceDate }
        let pose = FacePose.pose(
            spec: spec,
            mood: poseMood,
            time: time,
            budget: budget,
            pokePhase: pokePhase,
            motionEnabled: !reduceMotion
        )

        if pose.showsStandbyDash {
            drawStandby(context: context, side: side, light: light, time: time)
            return
        }
        drawEyes(pose: pose, context: context, side: side, color: eyeColor, morphScale: morphScale)
        drawThinkingDots(pose: pose, context: context, side: side, color: eyeColor)
        drawSleepZeds(pose: pose, context: context, side: side, color: eyeColor)
    }

    /// The clockless picker rendering: tile plus the family's still pose.
    private func drawStill(context: GraphicsContext, canvasSize: CGSize) {
        let side = min(canvasSize.width, canvasSize.height)
        let light = colorScheme != .dark
        let rgb = light ? spec.palette.eyeInk : spec.palette.eyeGlow
        let eyeColor = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        if showsTile {
            drawTile(context: context, side: side, light: light, eyeColor: eyeColor)
        }
        drawEyes(pose: .still(spec: spec), context: context, side: side, color: eyeColor, morphScale: 1)
    }

    private func drawTile(context: GraphicsContext, side: CGFloat, light: Bool, eyeColor: Color) {
        let tile = CGRect(x: 0.75, y: 0.75, width: side - 1.5, height: side - 1.5)
        let path = Path(roundedRect: tile, cornerRadius: side * 0.24)
        context.fill(path, with: .color(DevysColors.avatarTile))
        let border: Color = light ? .black.opacity(0.10) : .white.opacity(0.10)
        context.stroke(path, with: .color(border), lineWidth: max(1, side * 0.012))
        if !light && side >= 34 && mood != .off {
            let glow = Gradient(colors: [eyeColor.opacity(0.13), .clear])
            context.fill(
                Path(ellipseIn: tile),
                with: .radialGradient(
                    glow,
                    center: CGPoint(x: side / 2, y: side / 2),
                    startRadius: 1,
                    endRadius: side * 0.55
                )
            )
        }
    }

    private func drawEyes(
        pose: FacePose,
        context: GraphicsContext,
        side: CGFloat,
        color: Color,
        morphScale: Double
    ) {
        let faceInset = showsTile ? side * 0.03 : 0
        let span = side - faceInset * 2
        for eye in pose.eyes {
            let centerX = faceInset + eye.centerX * span
            let centerY = faceInset + eye.centerY * span
            let width = eye.width * span
            let height = max(eye.height * span * morphScale, side * 0.015)

            var layer = context
            layer.translateBy(x: centerX, y: centerY)
            layer.rotate(by: .radians(eye.tilt))

            switch eye.render {
            case .fill:
                let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
                layer.fill(
                    Path(roundedRect: rect, cornerRadius: max(eye.cornerRadius * span, 1)),
                    with: .color(color)
                )
            case .ring:
                let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
                layer.stroke(
                    Path(ellipseIn: rect.insetBy(dx: width * 0.14, dy: height * 0.14)),
                    with: .color(color),
                    lineWidth: max(width * 0.28, 2)
                )
            case .arc:
                var arc = Path()
                let radius = max(width, side * 0.16) * 0.62 * morphScale
                arc.addArc(
                    center: CGPoint(x: 0, y: radius * 0.45),
                    radius: radius,
                    startAngle: .radians(.pi * 1.15),
                    endAngle: .radians(.pi * 1.85),
                    clockwise: false
                )
                layer.stroke(
                    arc,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: max(side * 0.045, 2.5), lineCap: .round)
                )
            case .cross:
                let length = max(width, side * 0.14) * 0.9 * morphScale
                let thickness = max(side * 0.035, 2)
                for angle in [Double.pi / 4, -Double.pi / 4] {
                    var bar = layer
                    bar.rotate(by: .radians(angle))
                    let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
                    bar.fill(
                        Path(roundedRect: rect, cornerRadius: thickness / 2),
                        with: .color(color)
                    )
                }
            }
        }
    }

    private func drawThinkingDots(pose: FacePose, context: GraphicsContext, side: CGFloat, color: Color) {
        guard pose.thinkingDots > 0, side > 80, let eye = pose.eyes.last else { return }
        for index in 0..<pose.thinkingDots {
            let dot = CGRect(
                x: eye.centerX * side + side * 0.14 + CGFloat(index) * side * 0.05,
                y: side * 0.22,
                width: side * 0.028,
                height: side * 0.028
            )
            context.fill(Path(ellipseIn: dot), with: .color(color.opacity(0.75)))
        }
    }

    private struct ZedAnchor {
        var originX: CGFloat
        var originY: CGFloat
        var scale: CGFloat
        var alpha: Double
    }

    private func drawSleepZeds(pose: FacePose, context: GraphicsContext, side: CGFloat, color: Color) {
        guard pose.sleepZeds > 0 else { return }
        let anchors = [
            ZedAnchor(originX: 0.70, originY: 0.30, scale: 0.10, alpha: 0.85),
            ZedAnchor(originX: 0.80, originY: 0.18, scale: 0.07, alpha: 0.55)
        ]
        for (index, anchor) in anchors.enumerated() where index < pose.sleepZeds {
            let width = side * anchor.scale
            let originX = side * anchor.originX
            let originY = side * anchor.originY
            var zed = Path()
            zed.move(to: CGPoint(x: originX, y: originY))
            zed.addLine(to: CGPoint(x: originX + width, y: originY))
            zed.addLine(to: CGPoint(x: originX, y: originY + width * 0.9))
            zed.addLine(to: CGPoint(x: originX + width, y: originY + width * 0.9))
            context.stroke(
                zed,
                with: .color(color.opacity(anchor.alpha)),
                style: StrokeStyle(lineWidth: max(side * 0.024, 1.4), lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawStandby(context: GraphicsContext, side: CGFloat, light: Bool, time: Double) {
        let pulse = reduceMotion ? 0.3 : 0.22 + 0.14 * sin(time * 1.6)
        let dashWidth = side * 0.16
        let dash = CGRect(
            x: side / 2 - dashWidth / 2,
            y: side / 2 - side * 0.02,
            width: dashWidth,
            height: side * 0.04
        )
        let ink: Color = light ? .black : .white
        context.fill(
            Path(roundedRect: dash, cornerRadius: side * 0.02),
            with: .color(ink.opacity(pulse))
        )
    }
}
