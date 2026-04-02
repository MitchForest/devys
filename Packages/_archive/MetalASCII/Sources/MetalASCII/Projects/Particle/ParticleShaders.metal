// ParticleShaders.metal
// MetalASCII - GPU particle simulation and density rendering
//
// Copyright © 2026 Devys. All rights reserved.

#include <metal_stdlib>
using namespace metal;

// Include noise functions
#include "../../Core/Shaders/NoiseShaders.metal"

// MARK: - Particle Structure

struct Particle {
    float2 position;    // Current position
    float2 velocity;    // Current velocity
    float life;         // Remaining life (0-1)
    float age;          // Total age
    float brightness;   // Brightness contribution
    float size;         // Particle size
};

// MARK: - Uniforms

struct ParticleUniforms {
    float time;
    float deltaTime;
    float2 resolution;
    float2 center;
    float turbulence;
    float speed;
    float spawnRadius;
    float fadeSpeed;
    uint particleCount;
    uint cols;
    uint rows;
    uint ditherMode;
};

// MARK: - Bayer Dithering Matrix

constant float bayerMatrix8x8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
};

constant float bayerMatrix4x4[16] = {
     0,  8,  2, 10,
    12,  4, 14,  6,
     3, 11,  1,  9,
    15,  7, 13,  5
};

inline float applyDither(float brightness, uint2 pos, uint mode) {
    if (mode == 0) return brightness;  // No dithering
    
    if (mode == 1) {  // 4x4 Bayer
        uint x = pos.x % 4;
        uint y = pos.y % 4;
        float threshold = bayerMatrix4x4[y * 4 + x] / 16.0;
        return brightness + (threshold - 0.5) * 0.15;
    }
    
    // 8x8 Bayer (default)
    uint x = pos.x % 8;
    uint y = pos.y % 8;
    float threshold = bayerMatrix8x8[y * 8 + x] / 64.0;
    return brightness + (threshold - 0.5) * 0.1;
}

// MARK: - Particle Update Kernel

kernel void updateParticles(
    device Particle* particles [[buffer(0)]],
    constant ParticleUniforms& uniforms [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= uniforms.particleCount) return;
    
    Particle p = particles[gid];
    
    // Update age and life
    p.age += uniforms.deltaTime;
    p.life -= uniforms.deltaTime * uniforms.fadeSpeed;
    
    // Respawn dead particles
    if (p.life <= 0.0) {
        // Random angle based on particle ID and time
        float angle = simplex2D(float2(float(gid) * 0.1, uniforms.time * 0.5)) * 3.14159 * 2.0;
        float radius = (simplex2D(float2(float(gid) * 0.2, uniforms.time * 0.3)) * 0.5 + 0.5) * uniforms.spawnRadius;
        
        p.position = uniforms.center + float2(cos(angle), sin(angle)) * radius;
        p.velocity = float2(0.0);
        p.life = 0.5 + simplex2D(float2(float(gid) * 0.3, uniforms.time)) * 0.5;
        p.age = 0.0;
        p.brightness = 0.3 + simplex2D(float2(float(gid) * 0.4, uniforms.time * 0.7)) * 0.7;
        p.size = 0.5 + simplex2D(float2(float(gid) * 0.5, uniforms.time * 0.2)) * 0.5;
    }
    
    // Get flow field direction
    float2 flow = flowField(p.position * 2.0, uniforms.time, uniforms.turbulence);
    
    // Add spiral motion toward/away from center
    float2 toCenter = uniforms.center - p.position;
    float distToCenter = length(toCenter);
    float2 radial = normalize(toCenter);
    float2 tangent = float2(-radial.y, radial.x);
    
    // Combine forces
    float spiralStrength = 0.3 * (1.0 - smoothstep(0.0, 0.5, distToCenter));
    float2 acceleration = flow * uniforms.speed + 
                          tangent * spiralStrength * 0.5 +
                          radial * spiralStrength * 0.2;
    
    // Update velocity with damping
    p.velocity = p.velocity * 0.95 + acceleration * uniforms.deltaTime * 2.0;
    
    // Limit velocity
    float speed = length(p.velocity);
    if (speed > 0.02) {
        p.velocity = normalize(p.velocity) * 0.02;
    }
    
    // Update position
    p.position += p.velocity;
    
    // Fade brightness based on life
    p.brightness = p.brightness * smoothstep(0.0, 0.2, p.life) * smoothstep(1.0, 0.8, p.age);
    
    particles[gid] = p;
}

// MARK: - Density Accumulation Kernel

kernel void accumulateDensity(
    device const Particle* particles [[buffer(0)]],
    device atomic_uint* densityGrid [[buffer(1)]],
    constant ParticleUniforms& uniforms [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= uniforms.particleCount) return;
    
    Particle p = particles[gid];
    
    if (p.life <= 0.0 || p.brightness <= 0.01) return;
    
    // Convert position to grid coordinates
    float2 uv = p.position;
    int col = int(uv.x * float(uniforms.cols));
    int row = int((1.0 - uv.y) * float(uniforms.rows));  // Flip Y
    
    // Bounds check
    if (col < 0 || col >= int(uniforms.cols) || row < 0 || row >= int(uniforms.rows)) return;
    
    // Add brightness to density grid (scaled to integer)
    uint idx = row * uniforms.cols + col;
    uint brightness_int = uint(p.brightness * 1000.0 * p.size);
    atomic_fetch_add_explicit(&densityGrid[idx], brightness_int, memory_order_relaxed);
}

// MARK: - Brightness Normalization Kernel

kernel void normalizeDensity(
    device const atomic_uint* densityGrid [[buffer(0)]],
    device float* brightnessOutput [[buffer(1)]],
    constant ParticleUniforms& uniforms [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.cols || gid.y >= uniforms.rows) return;
    
    uint idx = gid.y * uniforms.cols + gid.x;
    uint rawDensity = atomic_load_explicit(&densityGrid[idx], memory_order_relaxed);
    
    // Normalize density to 0-1 range with soft clamping
    float density = float(rawDensity) / 1000.0;
    
    // Soft curve for more natural look
    float brightness = 1.0 - exp(-density * 0.5);
    
    // Apply dithering
    brightness = applyDither(brightness, gid, uniforms.ditherMode);
    
    brightnessOutput[idx] = clamp(brightness, 0.0, 1.0);
}

// MARK: - Clear Density Grid

kernel void clearDensityGrid(
    device atomic_uint* densityGrid [[buffer(0)]],
    constant ParticleUniforms& uniforms [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= uniforms.cols * uniforms.rows) return;
    atomic_store_explicit(&densityGrid[gid], 0, memory_order_relaxed);
}
