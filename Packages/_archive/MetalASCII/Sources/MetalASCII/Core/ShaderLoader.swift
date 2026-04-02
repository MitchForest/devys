// ShaderLoader.swift
// MetalASCII - Shader loading utilities for Swift Package resources
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import Metal
import Foundation

/// Utility for loading Metal shaders from Swift Package resources.
///
/// The loader tries multiple paths to find shaders:
/// 1. Compiled .metallib in bundle
/// 2. .metal source files in bundle
/// 3. Embedded source code as fallback
public enum ShaderLoader {

    // MARK: - Public API

    /// Load a Metal library from the bundle or embedded source.
    ///
    /// - Parameters:
    ///   - name: Shader name (e.g., "FlowerShaders")
    ///   - device: Metal device
    ///   - bundle: Optional bundle (defaults to module bundle)
    /// - Returns: Compiled Metal library
    public static func loadLibrary(
        named name: String,
        device: MTLDevice,
        bundle: Bundle? = nil
    ) throws -> MTLLibrary {
        let resolvedBundle = bundle ?? Bundle.module

        // Try compiled metallib first
        if let metallibURL = resolvedBundle.url(forResource: name, withExtension: "metallib") {
            return try device.makeLibrary(URL: metallibURL)
        }

        // Try .metal source
        if let metalURL = resolvedBundle.url(forResource: name, withExtension: "metal") {
            let source = try String(contentsOf: metalURL, encoding: .utf8)
            return try device.makeLibrary(source: source, options: nil)
        }

        // Try processed resources subdirectory
        if let metalURL = resolvedBundle.url(forResource: name, withExtension: "metal", subdirectory: "Core_Shaders") {
            let source = try String(contentsOf: metalURL, encoding: .utf8)
            return try device.makeLibrary(source: source, options: nil)
        }

        throw ShaderError.shaderNotFound(name)
    }

    /// Compile shader source directly.
    public static func compileShader(
        source: String,
        device: MTLDevice
    ) throws -> MTLLibrary {
        return try device.makeLibrary(source: source, options: nil)
    }

    /// Get the flower shader source (embedded for reliability).
    public static func getFlowerShaderSource() -> String {
        return flowerShaderSource
    }

    /// Get the ASCII art shader source (embedded for reliability).
    public static func getASCIIArtShaderSource() -> String {
        return asciiArtShaderSource
    }
}

// MARK: - Errors

public enum ShaderError: Error, LocalizedError {
    case shaderNotFound(String)
    case compilationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .shaderNotFound(let name):
            return "Shader '\(name)' not found in bundle"
        case .compilationFailed(let message):
            return "Shader compilation failed: \(message)"
        }
    }
}

// MARK: - Embedded Flower Shader Source

/// Embedded flower shader source for runtime compilation
private let flowerShaderSource = """
#include <metal_stdlib>
using namespace metal;

// Bayer 8x8 dithering matrix
constant float bayerMatrix8x8[64] = {
     0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0,
    48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0,
    12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0,
    60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0,
     3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0,
    51.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0,
    15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0,
    63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0
};

constant char asciiRamp[17] = " .,:;=+*#%@MWNBQ";

struct FlowerUniforms {
    float time;
    float windStrength;
    float windFrequency;
    float windSpeed;
    uint ditherMode;
    uint columns;
    uint rows;
    uint _pad0;
    float2 viewportSize;
    uint petalCount;
    uint petalLayers;
    float petalLength;
    float stemHeight;
    float bloomPhase;
    float _pad1;
    float _pad2;
    float _pad3;
};

// Simplex noise helpers
float3 grad3(int hash) {
    int h = hash & 15;
    float u = h < 8 ? 1.0 : -1.0;
    float v = h < 4 ? 1.0 : (h == 12 || h == 14 ? 1.0 : -1.0);
    float w = (h & 1) == 0 ? 1.0 : -1.0;
    return float3(u, v, w);
}

// Simple hash function
float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 2D noise
float noise2D(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal noise
float fbm(float2 p, float time) {
    float value = 0.0;
    float amplitude = 0.5;
    float2 shift = float2(time * 0.1, 0.0);

    for (int i = 0; i < 4; i++) {
        value += amplitude * noise2D(p + shift);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Generate flower brightness
float flowerBrightness(float2 uv, constant FlowerUniforms& uniforms) {
    float2 centered = uv - 0.5;
    float aspect = uniforms.viewportSize.x / uniforms.viewportSize.y;
    centered.x *= aspect;

    float r = length(centered);
    float theta = atan2(centered.y, centered.x);

    float brightness = 0.0;
    float k = float(uniforms.petalCount);

    for (uint layer = 0; layer < uniforms.petalLayers; layer++) {
        float layerScale = 1.0 - float(layer) * 0.15;
        float layerPhase = float(layer) * 0.4;

        // Wind using fractal noise
        float windTime = uniforms.time * uniforms.windSpeed;
        float windNoise = fbm(centered * 3.0 + float2(windTime, 0.0), windTime);
        float windOffset = (windNoise - 0.5) * uniforms.windStrength * (r * 2.5);

        float adjustedTheta = theta + windOffset;

        // Rose curve
        float petalR = abs(cos(k * adjustedTheta + layerPhase)) * uniforms.petalLength * layerScale;

        // Soft falloff
        float petalDist = r - petalR * 0.35;
        float petalMask = smoothstep(0.025, -0.015, petalDist);

        // Add vein details
        float veinAngle = fract(adjustedTheta * k / 6.28318 + layerPhase);
        float vein = smoothstep(0.48, 0.5, veinAngle) * smoothstep(0.52, 0.5, veinAngle);
        vein *= smoothstep(0.0, 0.2, r) * smoothstep(petalR * 0.35, 0.0, r);

        float layerBrightness = petalMask * (1.0 - float(layer) * 0.12);
        layerBrightness -= vein * 0.15;
        brightness = max(brightness, layerBrightness);
    }

    // Center
    float centerDist = length(centered);
    float center = smoothstep(0.045, 0.02, centerDist);
    brightness = max(brightness, center * 0.9);

    // Stem
    if (centered.y < -0.02 && abs(centered.x) < 0.012) {
        float stemTop = smoothstep(-0.02, -0.05, centered.y);
        float stemBottom = smoothstep(-uniforms.stemHeight - 0.1, -uniforms.stemHeight, centered.y);
        float stemMask = stemTop * stemBottom;
        brightness = max(brightness, stemMask * 0.5);
    }

    return clamp(brightness, 0.0, 1.0);
}

// Dithering
float bayerThreshold(uint2 pos, uint size) {
    uint x = pos.x % 8;
    uint y = pos.y % 8;
    return bayerMatrix8x8[y * 8 + x];
}

float applyDithering(float brightness, uint2 pos, uint mode) {
    if (mode == 0) return brightness;
    float threshold = bayerThreshold(pos, mode == 1 ? 4 : 8);
    float strength = mode == 1 ? 0.15 : 0.12;
    return brightness + (threshold - 0.5) * strength;
}

// Vertex shader
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut flowerVertex(
    uint vertexID [[vertex_id]],
    constant float2* vertices [[buffer(0)]]
) {
    VertexOut out;
    out.position = float4(vertices[vertexID], 0.0, 1.0);
    out.texCoord = (vertices[vertexID] + 1.0) * 0.5;
    out.texCoord.y = 1.0 - out.texCoord.y;
    return out;
}

// Fragment shader
fragment float4 flowerFragment(
    VertexOut in [[stage_in]],
    constant FlowerUniforms& uniforms [[buffer(0)]]
) {
    float brightness = flowerBrightness(in.texCoord, uniforms);
    return float4(brightness, brightness, brightness, 1.0);
}

// Compute shader for dither + ASCII
struct ASCIICell {
    uchar character;
    uchar brightness;
};

kernel void ditherAndConvert(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    device ASCIICell* outputCells [[buffer(0)]],
    constant FlowerUniforms& uniforms [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.columns || gid.y >= uniforms.rows) return;

    float2 texSize = float2(inputTexture.get_width(), inputTexture.get_height());
    float2 cellSize = texSize / float2(uniforms.columns, uniforms.rows);
    float2 samplePos = (float2(gid) + 0.5) * cellSize;

    // Sample and average
    float brightness = 0.0;
    int samples = 0;
    for (float dy = 0; dy < cellSize.y; dy += 2.0) {
        for (float dx = 0; dx < cellSize.x; dx += 2.0) {
            float2 pos = samplePos + float2(dx, dy) - cellSize * 0.5;
            if (pos.x >= 0 && pos.x < texSize.x && pos.y >= 0 && pos.y < texSize.y) {
                brightness += inputTexture.read(uint2(pos)).r;
                samples++;
            }
        }
    }
    brightness = samples > 0 ? brightness / float(samples) : 0.0;

    brightness = applyDithering(brightness, gid, uniforms.ditherMode);
    brightness = clamp(brightness, 0.0, 1.0);

    uint charIndex = uint(brightness * 15.0);
    charIndex = min(charIndex, 15u);

    uint cellIndex = gid.y * uniforms.columns + gid.x;
    outputCells[cellIndex].character = asciiRamp[charIndex];
    outputCells[cellIndex].brightness = uchar(brightness * 255.0);
}
"""

// MARK: - Embedded ASCII Art Shader Source

/// The working ASCII art shader from ASCIIArtShaders.metal
private let asciiArtShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct ASCIIUniforms {
    float2 viewportSize;
    float2 imageSize;
    float2 cellSize;
    float4 foregroundColor;
    float4 backgroundColor;
    uint   invertBrightness;
    float  contrastBoost;
    float  gamma;
    uint   charCount;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

inline float sampleBrightness(
    texture2d<float, access::sample> image,
    float2 uv,
    float gamma
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 color = image.sample(s, uv);
    float brightness = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
    return pow(brightness, gamma);
}

inline void sampleRegionWeights(
    texture2d<float, access::sample> image,
    float2 cellUVMin,
    float2 cellUVMax,
    float gamma,
    float contrast,
    bool invert,
    thread float* outWeights
) {
    float regions[9];

    for (int ry = 0; ry < 3; ry++) {
        for (int rx = 0; rx < 3; rx++) {
            float2 regionMin = float2(float(rx) / 3.0, float(ry) / 3.0);
            float2 regionMax = float2(float(rx + 1) / 3.0, float(ry + 1) / 3.0);

            float regionBrightness = 0.0;
            for (int sy = 0; sy < 2; sy++) {
                for (int sx = 0; sx < 2; sx++) {
                    float2 subPos = float2((float(sx) + 0.5) / 2.0, (float(sy) + 0.5) / 2.0);
                    float2 regionPos = mix(regionMin, regionMax, subPos);
                    float2 sampleUV = mix(cellUVMin, cellUVMax, regionPos);
                    regionBrightness += sampleBrightness(image, sampleUV, gamma);
                }
            }
            regionBrightness /= 4.0;

            if (invert) regionBrightness = 1.0 - regionBrightness;
            regionBrightness = (regionBrightness - 0.5) * contrast + 0.5;
            regionBrightness = clamp(regionBrightness, 0.0f, 1.0f);

            regions[ry * 3 + rx] = regionBrightness;
        }
    }

    float tl = regions[0], t = regions[1], tr = regions[2];
    float l = regions[3], m = regions[4], r = regions[5];
    float bl = regions[6], b = regions[7], br = regions[8];

    outWeights[0] = (tl + t + tr) / 3.0;
    outWeights[1] = (bl + b + br) / 3.0;
    outWeights[2] = (tl + l + bl) / 3.0;
    outWeights[3] = (tr + r + br) / 3.0;
    outWeights[4] = m;
}

inline int findBestCharacter(
    thread float* imageWeights,
    constant float* charWeights,
    constant int* charCodes,
    uint charCount
) {
    int bestChar = 32;
    float bestDistance = 999999.0;

    for (uint i = 0; i < charCount; i++) {
        float distance = 0.0;
        for (int w = 0; w < 5; w++) {
            distance += abs(imageWeights[w] - charWeights[i * 5 + w]);
        }
        if (distance < bestDistance) {
            bestDistance = distance;
            bestChar = charCodes[i];
        }
    }
    return bestChar;
}

inline float sampleFontTexture(
    texture2d<float, access::sample> fontTexture,
    int asciiCode,
    float2 cellPos
) {
    int charIndex = asciiCode - 32;
    if (charIndex < 0) charIndex = 0;
    if (charIndex > 94) charIndex = 94;

    float2 charOffset = float2(float(charIndex % 16), float(charIndex / 16));
    float2 gridSize = float2(16.0, 6.0);
    float2 uv = (charOffset + cellPos) / gridSize;

    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    return fontTexture.sample(s, uv).r;
}

vertex VertexOut asciiVertexShader(uint vertexID [[vertex_id]]) {
    VertexOut out;
    float2 positions[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
    float2 texCoords[4] = { float2(0,1), float2(1,1), float2(0,0), float2(1,0) };
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 asciiArtFragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> sourceImage [[texture(0)]],
    texture2d<float, access::sample> fontTexture [[texture(1)]],
    constant ASCIIUniforms& uniforms [[buffer(0)]],
    constant float* charWeights [[buffer(1)]],
    constant int* charCodes [[buffer(2)]]
) {
    float2 pixelPos = in.texCoord * uniforms.viewportSize;
    float2 cellIndex = floor(pixelPos / uniforms.cellSize);
    float2 cellPos = fract(pixelPos / uniforms.cellSize);
    float2 cellCount = floor(uniforms.viewportSize / uniforms.cellSize);

    float2 cellUVMin = cellIndex / cellCount;
    float2 cellUVMax = (cellIndex + 1.0) / cellCount;

    float imageAspect = uniforms.imageSize.x / uniforms.imageSize.y;
    float viewAspect = uniforms.viewportSize.x / uniforms.viewportSize.y;

    float2 uvOffset = float2(0.0);
    float2 uvScale = float2(1.0);

    if (imageAspect > viewAspect) {
        float scale = viewAspect / imageAspect;
        uvScale.y = scale;
        uvOffset.y = (1.0 - scale) * 0.5;
    } else {
        float scale = imageAspect / viewAspect;
        uvScale.x = scale;
        uvOffset.x = (1.0 - scale) * 0.5;
    }

    float2 imageCellUVMin = (cellUVMin - uvOffset) / uvScale;
    float2 imageCellUVMax = (cellUVMax - uvOffset) / uvScale;
    float2 cellCenter = (imageCellUVMin + imageCellUVMax) * 0.5;

    if (cellCenter.x < 0.0 || cellCenter.x > 1.0 || cellCenter.y < 0.0 || cellCenter.y > 1.0) {
        return uniforms.backgroundColor;
    }

    imageCellUVMin = clamp(imageCellUVMin, float2(0.0), float2(1.0));
    imageCellUVMax = clamp(imageCellUVMax, float2(0.0), float2(1.0));

    float imageWeights[5];
    sampleRegionWeights(
        sourceImage,
        imageCellUVMin,
        imageCellUVMax,
        uniforms.gamma,
        uniforms.contrastBoost,
        uniforms.invertBrightness != 0,
        imageWeights
    );

    int bestChar = findBestCharacter(imageWeights, charWeights, charCodes, uniforms.charCount);
    float charValue = sampleFontTexture(fontTexture, bestChar, cellPos);

    return mix(uniforms.backgroundColor, uniforms.foregroundColor, charValue);
}
"""

#endif // os(macOS)
