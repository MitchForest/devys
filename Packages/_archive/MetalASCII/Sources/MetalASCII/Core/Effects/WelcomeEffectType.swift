// WelcomeEffectType.swift
// DevysUI - Animated welcome screen effects
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

// MARK: - Welcome Effect Type

/// Available animated welcome screen effects rendered via Metal.
///
/// Each effect provides a unique visual experience for the welcome tab,
/// all running at 60fps with GPU acceleration.
public enum WelcomeEffectType: String, CaseIterable, Sendable {
    /// Floating particles connected by lines when within proximity.
    /// Gentle drift with noise-based velocity creates an organic feel.
    case constellation

    /// Particles following vector field patterns based on Perlin noise.
    /// Creates flowing, river-like motion across the screen.
    case flowField

    /// Falling ASCII characters like The Matrix.
    /// Characters fade as they fall, creating depth.
    case matrixRain

    /// Grid of points displaced by overlapping sine waves.
    /// Creates ocean-like undulation effect.
    case waveField

    /// Stars at multiple depth layers moving at different speeds.
    /// Classic parallax starfield effect.
    case starfield

    /// Wireframe mesh displaced by animated Perlin noise.
    /// Creates terrain-like morphing surface.
    case noiseMesh

    /// Particles in elliptical orbits around center.
    /// Atomic/planetary visual style.
    case orbits

    // MARK: - Display Properties

    /// Human-readable name for UI display
    public var displayName: String {
        switch self {
        case .constellation: return "Constellation"
        case .flowField: return "Flow Field"
        case .matrixRain: return "Matrix Rain"
        case .waveField: return "Wave Field"
        case .starfield: return "Starfield"
        case .noiseMesh: return "Noise Mesh"
        case .orbits: return "Orbits"
        }
    }

    /// Brief description of the effect
    public var description: String {
        switch self {
        case .constellation:
            return "Connected floating particles"
        case .flowField:
            return "Flowing particle streams"
        case .matrixRain:
            return "Falling ASCII characters"
        case .waveField:
            return "Undulating wave grid"
        case .starfield:
            return "Parallax star layers"
        case .noiseMesh:
            return "Morphing wireframe terrain"
        case .orbits:
            return "Orbital particle paths"
        }
    }

    // MARK: - Effect Parameters

    /// Default particle/element count for this effect
    public var defaultParticleCount: Int {
        switch self {
        case .constellation: return 150
        case .flowField: return 800
        case .matrixRain: return 60      // Column count
        case .waveField: return 2500     // 50x50 grid
        case .starfield: return 400
        case .noiseMesh: return 1600     // 40x40 grid
        case .orbits: return 200
        }
    }

    /// Shader effect type ID (matches Metal shader)
    public var shaderEffectID: UInt32 {
        switch self {
        case .constellation: return 0
        case .flowField: return 1
        case .matrixRain: return 2
        case .waveField: return 3
        case .starfield: return 4
        case .noiseMesh: return 5
        case .orbits: return 6
        }
    }

    /// Whether this effect uses compute shaders for particle updates
    public var usesComputeShader: Bool {
        switch self {
        case .constellation, .flowField, .starfield, .orbits:
            return true
        case .matrixRain, .waveField, .noiseMesh:
            return false  // Vertex shader only
        }
    }

    /// Whether this effect renders lines (vs just points)
    public var rendersLines: Bool {
        switch self {
        case .constellation, .noiseMesh:
            return true
        default:
            return false
        }
    }
}

// MARK: - Random Selection

public extension WelcomeEffectType {
    /// Returns a random effect type
    static var random: WelcomeEffectType {
        allCases.randomElement() ?? .constellation
    }

    /// Returns a random effect, excluding specific types
    static func random(excluding: Set<WelcomeEffectType>) -> WelcomeEffectType {
        let available = allCases.filter { !excluding.contains($0) }
        return available.randomElement() ?? .constellation
    }
}
