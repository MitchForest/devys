import Foundation
import Testing
@testable import DevysCharacter

@Suite("Face model")
struct FacePoseTests {
    @Test("Every shape maps to its eye family")
    func familyMapping() {
        #expect(EyeFamily(shape: .circle) == .round)
        #expect(EyeFamily(shape: .roundedSquare) == .squircle)
        #expect(EyeFamily(shape: .capsule) == .capsule)
        #expect(EyeFamily(shape: .blob) == .wide)
        #expect(EyeFamily(shape: .triangle) == .keen)
        #expect(EyeFamily(shape: .hexagon) == .ring)
        #expect(EyeFamily(shape: .cloud) == .dot)
        #expect(EyeFamily(shape: .drop) == .tall)
    }

    @Test("Every palette has displayable ink and glow eye colors")
    func eyeColorRange() {
        for palette in AvatarPalette.allCases {
            for tone in [palette.eyeInk, palette.eyeGlow] {
                #expect((0...1).contains(tone.red))
                #expect((0...1).contains(tone.green))
                #expect((0...1).contains(tone.blue))
            }
            // Glow is brighter than ink: the dual ramp is real.
            let inkSum = palette.eyeInk.red + palette.eyeInk.green + palette.eyeInk.blue
            let glowSum = palette.eyeGlow.red + palette.eyeGlow.green + palette.eyeGlow.blue
            #expect(glowSum > inkSum)
        }
    }

    @Test("Temperament is a pure function of the seed")
    func temperamentDeterminism() {
        let first = Temperament(seed: 11)
        let second = Temperament(seed: 11)
        #expect(first == second)
        #expect(first.blinkPeriod >= 2.8)
        #expect(first.blinkPeriod <= 6.2)
    }

    @Test("Two seeds give two temperaments a renderer can tell apart")
    func seedsDiffer() {
        let periods = (0..<16).map { Temperament(seed: $0).blinkPeriod }
        #expect(Set(periods).count > 4)
    }

    @Test("Poses are deterministic and stay on the face", arguments: AvatarShape.allCases)
    func poseBounds(shape: AvatarShape) {
        let spec = AvatarSpec(palette: .blue, shape: shape, seed: 21)
        let budgets: [MotionBudget] = [.minimal, .poses, .full]
        for mood in BotMood.allCases {
            for budget in budgets {
                for step in 0..<8 {
                    let time = Double(step) * 0.73
                    let pose = FacePose.pose(spec: spec, mood: mood, time: time, budget: budget)
                    let again = FacePose.pose(spec: spec, mood: mood, time: time, budget: budget)
                    #expect(pose == again)
                    if mood == .off {
                        #expect(pose.eyes.isEmpty)
                        #expect(pose.showsStandbyDash)
                        continue
                    }
                    #expect(pose.eyes.count == 2)
                    for eye in pose.eyes {
                        #expect(eye.centerX > 0.1 && eye.centerX < 0.9)
                        #expect(eye.centerY > 0.1 && eye.centerY < 0.9)
                        #expect(eye.width > 0 && eye.width < 0.6)
                        #expect(eye.height > 0 && eye.height < 0.7)
                    }
                }
            }
        }
    }

    @Test("Minimal budget is still apart from the blink clock", arguments: AvatarShape.allCases)
    func minimalBudgetIsStill(shape: AvatarShape) {
        let spec = AvatarSpec(palette: .teal, shape: shape, seed: 5)
        let temperament = Temperament(seed: 5)
        // Two times outside any blink window.
        let times = [1.0, 6.3].map { candidate in
            var time = candidate
            while temperament.isBlinking(at: time) { time += 0.2 }
            return time
        }
        let first = FacePose.pose(spec: spec, mood: .idle, time: times[0], budget: .minimal)
        let later = FacePose.pose(spec: spec, mood: .idle, time: times[1], budget: .minimal)
        #expect(first == later)
    }

    @Test("The emotional alphabet renders as designed")
    func expressionAlphabet() {
        let spec = AvatarSpec(palette: .pink, shape: .circle, seed: 8)
        // Sample away from blink windows so height comparisons are fair.
        let temperament = Temperament(seed: 8)
        var time = 1.0
        while temperament.isBlinking(at: time) { time += 0.2 }

        func pose(_ mood: BotMood) -> FacePose {
            FacePose.pose(spec: spec, mood: mood, time: time, budget: .poses)
        }
        #expect(pose(.celebrate).eyes.allSatisfy { $0.render == .arc })
        #expect(pose(.oops).eyes.allSatisfy { $0.render == .cross })
        #expect(pose(.asleep).eyes[0].height < pose(.idle).eyes[0].height)
        // Asleep carries the z glyph at readable sizes, never at minimal.
        #expect(pose(.asleep).sleepZeds > 0)
        let tiny = FacePose.pose(spec: spec, mood: .asleep, time: time, budget: .minimal)
        #expect(tiny.sleepZeds == 0)
        #expect(pose(.working).eyes[0].height < pose(.thinking).eyes[0].height)
        // Waiting raises the right eye — the quizzical eyebrow.
        let waiting = pose(.waiting)
        #expect(waiting.eyes[1].centerY < waiting.eyes[0].centerY)
        // Thinking looks up and away.
        let thinking = pose(.thinking)
        #expect(thinking.eyes[0].centerY < pose(.idle).eyes[0].centerY)
    }

    @Test("Poke flashes happy crescents at full budget only")
    func pokeIsHeroOnly() {
        let spec = AvatarSpec(palette: .amber, shape: .drop, seed: 3)
        let poked = FacePose.pose(spec: spec, mood: .idle, time: 2, budget: .full, pokePhase: 0.2)
        #expect(poked.eyes.allSatisfy { $0.render == .arc })
        let small = FacePose.pose(spec: spec, mood: .idle, time: 2, budget: .poses, pokePhase: 0.2)
        #expect(small.eyes.allSatisfy { $0.render != .arc })
    }

    @Test("Reduce Motion freezes the gaze wander")
    func reducedMotion() {
        let spec = AvatarSpec(palette: .purple, shape: .hexagon, seed: 9)
        let temperament = Temperament(seed: 9)
        let times = [1.0, 4.0].map { candidate in
            var time = candidate
            while temperament.isBlinking(at: time) { time += 0.2 }
            return time
        }
        let first = FacePose.pose(spec: spec, mood: .idle, time: times[0], budget: .full, motionEnabled: false)
        let later = FacePose.pose(spec: spec, mood: .idle, time: times[1], budget: .full, motionEnabled: false)
        #expect(first == later)
    }

    @Test("Still picker poses are calm, open-eyed, and clockless")
    func stillPosesAreCalm() {
        for shape in AvatarShape.allCases {
            let spec = AvatarSpec(palette: .blue, shape: shape, seed: 9)
            let pose = FacePose.still(spec: spec)
            let geometry = EyeFamily(shape: shape).geometry
            #expect(!pose.showsStandbyDash)
            #expect(pose.thinkingDots == 0)
            #expect(pose.sleepZeds == 0)
            #expect(pose.eyes.count == 2)
            for eye in pose.eyes {
                // Fully open — never a blink, slit, or expression glyph.
                #expect(eye.height == geometry.height)
                #expect(eye.render == (geometry.isRing ? .ring : .fill))
            }
            // Seed only shapes motion, so a still pose ignores it.
            #expect(pose == FacePose.still(spec: AvatarSpec(palette: .blue, shape: shape, seed: 40)))
        }
    }

    @Test("Every family's still pose is distinct from every other's")
    func stillPosesDiffer() {
        let poses = AvatarShape.allCases.map { shape in
            FacePose.still(spec: AvatarSpec(palette: .blue, shape: shape, seed: 9))
        }
        for (index, pose) in poses.enumerated() {
            for other in poses[poses.index(after: index)...] {
                #expect(pose != other)
            }
        }
    }
}
