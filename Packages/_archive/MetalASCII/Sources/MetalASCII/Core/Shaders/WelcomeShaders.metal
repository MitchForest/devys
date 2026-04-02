// WelcomeShaders.metal
// DevysUI - GPU shaders for animated welcome effects
//
// Provides buttery smooth 60fps particle systems, wave fields,
// and other procedural visual effects for welcome tabs.
//
// Copyright © 2026 Devys. All rights reserved.

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared Structures

/// Per-frame uniforms passed from Swift
struct WelcomeUniforms {
    float2 viewportSize;        // Screen dimensions in pixels
    float time;                 // Animation time in seconds
    float deltaTime;            // Frame delta time
    float4 accentColor;         // Theme accent color (RGBA)
    float4 backgroundColor;     // Theme background color
    uint effectType;            // Which effect to render
    uint particleCount;         // Active particle/element count
    float effectParam1;         // Effect-specific parameter
    float effectParam2;
    float effectParam3;
    float effectParam4;
};

/// Individual particle data
struct Particle {
    float2 position;            // Screen position in pixels
    float2 velocity;            // Movement vector
    float life;                 // 0-1 lifecycle (1 = fresh, 0 = dead)
    float size;                 // Point size in pixels
    float brightness;           // Alpha/intensity multiplier
    uint flags;                 // Effect-specific flags
};

/// Matrix rain column data
struct MatrixColumn {
    float yOffset;              // Current Y position of head
    float speed;                // Fall speed in pixels/sec
    uint characterSeed;         // Random seed for character selection
    float brightness;           // Column brightness
};

/// Vertex shader output for particles
struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
    float life;
};

/// Vertex shader output for lines
struct LineVertexOut {
    float4 position [[position]];
    float4 color;
};

/// Vertex shader output for wave/grid effects
struct GridVertexOut {
    float4 position [[position]];
    float4 color;
    float2 gridCoord;
};

// MARK: - Noise Functions

/// Simple hash function for pseudo-random values
inline float hash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

/// 2D value noise
inline float noise2D(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    
    // Smooth interpolation
    float2 u = f * f * (3.0 - 2.0 * f);
    
    // Four corners
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Fractal Brownian Motion (layered noise)
inline float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise2D(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

// MARK: - Compute Shader: Particle Update

/// Updates particle positions and lifecycle each frame.
/// Used by constellation, flow field, starfield, and orbits effects.
kernel void updateParticles(
    device Particle *particles [[buffer(0)]],
    constant WelcomeUniforms &uniforms [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= uniforms.particleCount) return;
    
    Particle p = particles[id];
    float2 viewport = uniforms.viewportSize;
    
    // Effect-specific behavior
    switch (uniforms.effectType) {
        case 0: // Constellation - gentle drift
        {
            // Add subtle noise-based turbulence
            float2 noiseCoord = p.position * 0.005 + uniforms.time * 0.1;
            float angle = noise2D(noiseCoord) * 6.28318;
            float2 turbulence = float2(cos(angle), sin(angle)) * 5.0;
            
            p.velocity = p.velocity * 0.98 + turbulence * 0.02;
            p.position += p.velocity * uniforms.deltaTime;
            break;
        }
        
        case 1: // Flow field - follow noise vectors
        {
            float2 noiseCoord = p.position * uniforms.effectParam1 * 0.003;
            float angle = fbm(noiseCoord + uniforms.time * 0.05, 3) * 6.28318 * 2.0;
            float speed = uniforms.effectParam2 * 100.0;
            
            p.velocity = float2(cos(angle), sin(angle)) * speed;
            p.position += p.velocity * uniforms.deltaTime;
            
            // Leave trail by reducing brightness over time
            p.brightness = 0.3 + noise2D(p.position * 0.1) * 0.7;
            break;
        }
        
        case 4: // Starfield - parallax movement
        {
            // Layer based on particle ID
            float layer = float(id % 4) + 1.0;
            float speed = uniforms.effectParam1 * 50.0 / layer;
            
            p.position.x -= speed * uniforms.deltaTime;
            p.size = 1.0 + (4.0 - layer) * 1.5;
            p.brightness = 0.3 + (4.0 - layer) * 0.2;
            break;
        }
        
        case 6: // Orbits - elliptical paths
        {
            float orbitIndex = float(id % 8);
            float particlePhase = float(id) * 0.1;
            
            float a = viewport.x * 0.15 * (1.0 + orbitIndex * 0.15);  // Semi-major
            float b = viewport.y * 0.1 * (1.0 + orbitIndex * 0.12);   // Semi-minor
            float speed = uniforms.effectParam1 * (0.5 + orbitIndex * 0.1);
            
            float angle = uniforms.time * speed + particlePhase;
            
            p.position = viewport * 0.5 + float2(
                cos(angle) * a,
                sin(angle) * b
            );
            
            p.brightness = 0.5 + sin(angle * 3.0) * 0.3;
            break;
        }
        
        default:
            p.position += p.velocity * uniforms.deltaTime;
            break;
    }
    
    // Wrap around screen edges (toroidal topology)
    if (p.position.x < 0) p.position.x += viewport.x;
    if (p.position.x > viewport.x) p.position.x -= viewport.x;
    if (p.position.y < 0) p.position.y += viewport.y;
    if (p.position.y > viewport.y) p.position.y -= viewport.y;
    
    // Update life (for effects that use lifecycle)
    if (uniforms.effectType == 1) { // Flow field respawn
        p.life -= uniforms.deltaTime * 0.2;
        if (p.life <= 0) {
            p.life = 1.0;
            // Respawn at random edge
            float edge = hash(float2(float(id), uniforms.time));
            if (edge < 0.25) {
                p.position = float2(0, hash(float2(uniforms.time, float(id))) * viewport.y);
            } else if (edge < 0.5) {
                p.position = float2(viewport.x, hash(float2(float(id), uniforms.time * 2.0)) * viewport.y);
            } else if (edge < 0.75) {
                p.position = float2(hash(float2(uniforms.time * 3.0, float(id))) * viewport.x, 0);
            } else {
                p.position = float2(hash(float2(float(id), uniforms.time * 4.0)) * viewport.x, viewport.y);
            }
        }
    }
    
    particles[id] = p;
}

// MARK: - Vertex Shaders

/// Constellation/Flow particle vertex shader
vertex ParticleVertexOut particleVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant Particle *particles [[buffer(0)]],
    constant WelcomeUniforms &uniforms [[buffer(1)]]
) {
    Particle p = particles[instanceID];
    
    // Convert to normalized device coordinates
    float2 ndc = (p.position / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;  // Flip Y for Metal coordinate system
    
    ParticleVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.pointSize = p.size * (0.5 + p.life * 0.5);
    out.color = uniforms.accentColor * p.brightness;
    out.life = p.life;
    
    return out;
}

/// Wave field vertex shader
vertex GridVertexOut waveFieldVertex(
    uint vertexID [[vertex_id]],
    constant WelcomeUniforms &uniforms [[buffer(0)]]
) {
    // Grid layout (effectParam1 = grid size, e.g. 50)
    uint gridSize = uint(uniforms.effectParam1);
    if (gridSize == 0) gridSize = 50;
    
    uint x = vertexID % gridSize;
    uint y = vertexID / gridSize;
    
    float2 gridPos = float2(float(x), float(y)) / float(gridSize - 1);
    float2 screenPos = gridPos * uniforms.viewportSize;
    
    // Multiple overlapping sine waves
    float waveAmp = uniforms.effectParam2 * 30.0;
    float wave1 = sin(gridPos.x * 8.0 + uniforms.time * 2.0) * waveAmp;
    float wave2 = sin(gridPos.y * 6.0 + uniforms.time * 1.5) * waveAmp * 0.7;
    float wave3 = sin((gridPos.x + gridPos.y) * 5.0 + uniforms.time * 1.2) * waveAmp * 0.5;
    float wave4 = sin(gridPos.x * 12.0 - uniforms.time * 0.8) * waveAmp * 0.3;
    
    float displacement = wave1 + wave2 + wave3 + wave4;
    screenPos.y += displacement;
    
    // Convert to NDC
    float2 ndc = (screenPos / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    
    // Color based on wave height
    float normalizedHeight = displacement / (waveAmp * 3.0) * 0.5 + 0.5;
    float intensity = 0.3 + normalizedHeight * 0.5;
    
    GridVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = uniforms.accentColor * intensity;
    out.gridCoord = gridPos;
    
    return out;
}

/// Noise mesh vertex shader (wireframe terrain)
vertex GridVertexOut noiseMeshVertex(
    uint vertexID [[vertex_id]],
    constant WelcomeUniforms &uniforms [[buffer(0)]]
) {
    uint gridSize = uint(uniforms.effectParam1);
    if (gridSize == 0) gridSize = 40;
    
    uint x = vertexID % gridSize;
    uint y = vertexID / gridSize;
    
    float2 gridPos = float2(float(x), float(y)) / float(gridSize - 1);
    float2 screenPos = gridPos * uniforms.viewportSize;
    
    // Animated Perlin noise displacement
    float2 noiseCoord = gridPos * uniforms.effectParam2 * 4.0;
    noiseCoord += uniforms.time * 0.15;
    
    float height = fbm(noiseCoord, 4) * uniforms.effectParam3 * 100.0;
    screenPos.y += height - uniforms.effectParam3 * 50.0;  // Center vertically
    
    float2 ndc = (screenPos / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    
    // Brightness based on height
    float normalizedHeight = height / (uniforms.effectParam3 * 100.0);
    float intensity = 0.2 + normalizedHeight * 0.6;
    
    GridVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = uniforms.accentColor * intensity;
    out.gridCoord = gridPos;
    
    return out;
}

/// Matrix rain vertex shader
vertex ParticleVertexOut matrixRainVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant MatrixColumn *columns [[buffer(0)]],
    constant WelcomeUniforms &uniforms [[buffer(1)]]
) {
    MatrixColumn col = columns[instanceID];
    
    float charWidth = 12.0;
    float charHeight = 18.0;
    uint trailLength = 25;
    uint charIndex = vertexID % trailLength;
    
    float x = float(instanceID) * charWidth + charWidth * 0.5;
    float y = col.yOffset - float(charIndex) * charHeight;
    
    // Wrap Y
    float screenHeight = uniforms.viewportSize.y;
    y = fmod(y + screenHeight * 2.0, screenHeight + charHeight * float(trailLength)) - charHeight * float(trailLength);
    
    float2 ndc = (float2(x, y) / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    
    // Fade based on position in trail (head is brightest)
    float fade = 1.0 - float(charIndex) / float(trailLength);
    fade = pow(fade, 1.5);  // Non-linear falloff
    
    // Head character is extra bright
    if (charIndex == 0) {
        fade = 1.2;
    }
    
    ParticleVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.pointSize = charHeight * 0.8;
    out.color = uniforms.accentColor * fade * col.brightness;
    out.life = fade;
    
    return out;
}

// MARK: - Fragment Shaders

/// Particle fragment shader with soft circular glow
fragment float4 particleFragment(
    ParticleVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    // Distance from center of point sprite
    float dist = length(pointCoord - 0.5) * 2.0;
    
    // Soft circular falloff
    float alpha = 1.0 - smoothstep(0.0, 1.0, dist);
    
    // Add glow halo
    float glow = exp(-dist * 2.0) * 0.5;
    alpha = max(alpha, glow);
    
    return float4(in.color.rgb, in.color.a * alpha);
}

/// Grid/wave field fragment shader
fragment float4 gridFragment(GridVertexOut in [[stage_in]]) {
    return in.color;
}

/// Matrix rain fragment shader (simplified - no font texture for now)
fragment float4 matrixRainFragment(
    ParticleVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    // Simple rectangular character cell
    float2 uv = pointCoord;
    
    // Create simple character-like pattern using noise
    float pattern = hash(floor(uv * 4.0 + in.life * 10.0));
    
    // Soften edges
    float edgeFade = smoothstep(0.0, 0.1, uv.x) * smoothstep(1.0, 0.9, uv.x);
    edgeFade *= smoothstep(0.0, 0.1, uv.y) * smoothstep(1.0, 0.9, uv.y);
    
    float alpha = pattern * edgeFade * in.color.a;
    
    return float4(in.color.rgb, alpha);
}

// MARK: - Connection Lines (Constellation)

/// Line vertex for constellation connections
vertex LineVertexOut connectionLineVertex(
    uint vertexID [[vertex_id]],
    constant float4 *lineData [[buffer(0)]],  // xy = position, z = alpha, w = unused
    constant WelcomeUniforms &uniforms [[buffer(1)]]
) {
    float4 v = lineData[vertexID];
    
    float2 ndc = (v.xy / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    
    LineVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = float4(uniforms.accentColor.rgb, v.z * 0.4);  // Subtle lines
    
    return out;
}

/// Line fragment shader
fragment float4 lineFragment(LineVertexOut in [[stage_in]]) {
    return in.color;
}
