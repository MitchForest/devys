import Foundation

/// Seed-derived motion personality: two Bots with the same family and
/// color still blink and glance on their own clocks.
struct Temperament: Equatable {
    var blinkPeriod: Double
    var blinkPhase: Double
    var wanderRate: Double
    var wanderPhase: Double
    var wanderAmp: Double

    init(seed: Int) {
        var generator = SeededGenerator(seed: seed)
        blinkPeriod = 2.8 + Double(generator.next(upTo: 34)) / 10
        blinkPhase = Double(generator.next(upTo: 100)) / 100 * blinkPeriod
        wanderRate = 0.16 + Double(generator.next(upTo: 16)) / 100
        wanderPhase = Double(generator.next(upTo: 628)) / 100
        wanderAmp = 0.35 + Double(generator.next(upTo: 50)) / 100
    }

    func isBlinking(at time: Double) -> Bool {
        (time + blinkPhase).truncatingRemainder(dividingBy: blinkPeriod) < 0.16
    }

    /// 0→1→0 within the blink window for a soft lid rather than a snap.
    func blinkCloseness(at time: Double) -> Double {
        guard isBlinking(at: time) else { return 0 }
        let cycle = (time + blinkPhase).truncatingRemainder(dividingBy: blinkPeriod)
        return 1 - abs(cycle / 0.08 - 1)
    }
}

/// Deterministic tiny generator so face variation never depends on
/// process randomness.
struct SeededGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &* 6_364_136_223_846_793_005 &+ 1
    }

    mutating func next(upTo bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int(truncatingIfNeeded: (state >> 33) % UInt64(max(bound, 1)))
    }
}
