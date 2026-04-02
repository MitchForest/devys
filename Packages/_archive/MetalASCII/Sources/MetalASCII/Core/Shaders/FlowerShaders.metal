// FlowerShaders.metal
// MetalASCII - Procedural flower with dithering and wind animation
//
// Copyright © 2026 Devys. All rights reserved.

#include <metal_stdlib>
using namespace metal;

// MARK: - Constants

// Bayer 8x8 dithering matrix (normalized to 0-1)
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

// ASCII character ramp (16 characters from dark to light)
// " .:-=+*#%@" extended
constant char asciiRamp[17] = " .,:;=+*#%@MWNBQ";

// MARK: - Uniforms

struct FlowerUniforms {
    float time;
    float windStrength;
    float windFrequency;
    float windSpeed;
    uint ditherMode;      // 0=none, 1=bayer4x4, 2=bayer8x8
    uint columns;         // ASCII columns
    uint rows;            // ASCII rows
    float2 viewportSize;
    uint petalCount;
    uint petalLayers;
    float petalLength;
    float stemHeight;
    float bloomPhase;     // 0-1 for bloom animation
};

// MARK: - Simplex Noise (3D)

// Permutation table
constant int perm[512] = {
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,
    8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,
    35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,
    134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,
    55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,
    18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,
    250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,
    189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,
    172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,
    228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,
    107,49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180,
    // Repeat
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,
    8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,
    35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,
    134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,
    55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,
    18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,
    250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,
    189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,
    172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,
    228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,
    107,49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
};

float3 grad3(int hash) {
    int h = hash & 15;
    float u = h < 8 ? 1.0 : -1.0;
    float v = h < 4 ? 1.0 : (h == 12 || h == 14 ? 1.0 : -1.0);
    float w = (h & 1) == 0 ? 1.0 : -1.0;
    return float3(u, v, w);
}

float simplex3D(float3 pos) {
    // Skew factors for 3D
    const float F3 = 1.0 / 3.0;
    const float G3 = 1.0 / 6.0;
    
    // Skew input space
    float s = (pos.x + pos.y + pos.z) * F3;
    int i = int(floor(pos.x + s));
    int j = int(floor(pos.y + s));
    int k = int(floor(pos.z + s));
    
    // Unskew
    float t = float(i + j + k) * G3;
    float3 origin = float3(float(i) - t, float(j) - t, float(k) - t);
    float3 d0 = pos - origin;
    
    // Determine simplex
    int3 i1, i2;
    if (d0.x >= d0.y) {
        if (d0.y >= d0.z) { i1 = int3(1,0,0); i2 = int3(1,1,0); }
        else if (d0.x >= d0.z) { i1 = int3(1,0,0); i2 = int3(1,0,1); }
        else { i1 = int3(0,0,1); i2 = int3(1,0,1); }
    } else {
        if (d0.y < d0.z) { i1 = int3(0,0,1); i2 = int3(0,1,1); }
        else if (d0.x < d0.z) { i1 = int3(0,1,0); i2 = int3(0,1,1); }
        else { i1 = int3(0,1,0); i2 = int3(1,1,0); }
    }
    
    float3 d1 = d0 - float3(i1) + G3;
    float3 d2 = d0 - float3(i2) + 2.0 * G3;
    float3 d3 = d0 - 1.0 + 3.0 * G3;
    
    // Hash coordinates
    int ii = i & 255;
    int jj = j & 255;
    int kk = k & 255;
    
    int g0 = perm[ii + perm[jj + perm[kk]]];
    int g1 = perm[ii + i1.x + perm[jj + i1.y + perm[kk + i1.z]]];
    int g2 = perm[ii + i2.x + perm[jj + i2.y + perm[kk + i2.z]]];
    int g3 = perm[ii + 1 + perm[jj + 1 + perm[kk + 1]]];
    
    // Contributions
    float n0 = 0.0, n1 = 0.0, n2 = 0.0, n3 = 0.0;
    
    float t0 = 0.6 - dot(d0, d0);
    if (t0 > 0) { t0 *= t0; n0 = t0 * t0 * dot(grad3(g0), d0); }
    
    float t1 = 0.6 - dot(d1, d1);
    if (t1 > 0) { t1 *= t1; n1 = t1 * t1 * dot(grad3(g1), d1); }
    
    float t2 = 0.6 - dot(d2, d2);
    if (t2 > 0) { t2 *= t2; n2 = t2 * t2 * dot(grad3(g2), d2); }
    
    float t3 = 0.6 - dot(d3, d3);
    if (t3 > 0) { t3 *= t3; n3 = t3 * t3 * dot(grad3(g3), d3); }
    
    return 32.0 * (n0 + n1 + n2 + n3);
}

// MARK: - Flower Geometry

// Polar rose curve: r = cos(k * theta)
float petalShape(float theta, float k, float phase) {
    return cos(k * theta + phase);
}

// Generate petal brightness at a point
float flowerBrightness(float2 uv, constant FlowerUniforms& uniforms) {
    // Center the coordinates
    float2 centered = uv - 0.5;
    
    // Account for aspect ratio
    float aspect = uniforms.viewportSize.x / uniforms.viewportSize.y;
    centered.x *= aspect;
    
    // Convert to polar coordinates
    float r = length(centered);
    float theta = atan2(centered.y, centered.x);
    
    float brightness = 0.0;
    float k = float(uniforms.petalCount);
    
    // Generate multiple petal layers
    for (uint layer = 0; layer < uniforms.petalLayers; layer++) {
        float layerScale = 1.0 - float(layer) * 0.2;
        float layerPhase = float(layer) * 0.5;
        
        // Wind displacement using simplex noise
        float windTime = uniforms.time * uniforms.windSpeed;
        float windNoise = simplex3D(float3(
            centered.x * 2.0,
            centered.y * 2.0,
            windTime + float(layer) * 0.3
        ));
        
        // Apply wind to petal angle
        float windOffset = windNoise * uniforms.windStrength * (r * 2.0);
        float adjustedTheta = theta + windOffset;
        
        // Rose curve for petal shape
        float petalR = abs(petalShape(adjustedTheta, k, layerPhase)) * uniforms.petalLength * layerScale;
        
        // Soft falloff from petal edge
        float petalDist = r - petalR * 0.3;
        float petalMask = smoothstep(0.02, -0.01, petalDist);
        
        // Add petal brightness with layer fade
        float layerBrightness = petalMask * (1.0 - float(layer) * 0.15);
        brightness = max(brightness, layerBrightness);
    }
    
    // Add center (pistil)
    float centerDist = length(centered);
    float center = smoothstep(0.05, 0.02, centerDist);
    brightness = max(brightness, center * 0.8);
    
    // Add stem
    if (centered.y < 0.0 && abs(centered.x) < 0.015) {
        float stemMask = smoothstep(-0.02, 0.0, centered.y + uniforms.stemHeight);
        brightness = max(brightness, stemMask * 0.6);
    }
    
    return clamp(brightness, 0.0, 1.0);
}

// MARK: - Dithering

float bayerThreshold(uint2 pos, uint size) {
    if (size == 8) {
        uint x = pos.x % 8;
        uint y = pos.y % 8;
        return bayerMatrix8x8[y * 8 + x];
    } else {
        // 4x4 subset
        uint x = pos.x % 4;
        uint y = pos.y % 4;
        uint idx = y * 8 + x * 2;
        return bayerMatrix8x8[idx];
    }
}

float applyDithering(float brightness, uint2 pos, uint mode) {
    if (mode == 0) {
        // No dithering
        return brightness;
    } else if (mode == 1) {
        // Bayer 4x4
        float threshold = bayerThreshold(pos, 4);
        return brightness + (threshold - 0.5) * 0.15;
    } else {
        // Bayer 8x8
        float threshold = bayerThreshold(pos, 8);
        return brightness + (threshold - 0.5) * 0.12;
    }
}

// MARK: - Vertex Shader

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
    out.texCoord.y = 1.0 - out.texCoord.y; // Flip Y
    return out;
}

// MARK: - Fragment Shader (Render to Texture)

fragment float4 flowerFragment(
    VertexOut in [[stage_in]],
    constant FlowerUniforms& uniforms [[buffer(0)]]
) {
    float brightness = flowerBrightness(in.texCoord, uniforms);
    return float4(brightness, brightness, brightness, 1.0);
}

// MARK: - Compute Shader (Dither + ASCII Conversion)

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
    if (gid.x >= uniforms.columns || gid.y >= uniforms.rows) {
        return;
    }
    
    // Sample the flower texture
    float2 texSize = float2(inputTexture.get_width(), inputTexture.get_height());
    float2 cellSize = texSize / float2(uniforms.columns, uniforms.rows);
    float2 samplePos = (float2(gid) + 0.5) * cellSize;
    
    // Average brightness over the cell
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
    
    // Apply dithering
    brightness = applyDithering(brightness, gid, uniforms.ditherMode);
    brightness = clamp(brightness, 0.0, 1.0);
    
    // Convert to ASCII character index (0-15)
    uint charIndex = uint(brightness * 15.0);
    charIndex = min(charIndex, 15u);
    
    // Store result
    uint cellIndex = gid.y * uniforms.columns + gid.x;
    outputCells[cellIndex].character = asciiRamp[charIndex];
    outputCells[cellIndex].brightness = uchar(brightness * 255.0);
}

// MARK: - ASCII Rendering (Character Display)

struct ASCIIVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float brightness;
    uint charIndex;
};

vertex ASCIIVertexOut asciiVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant float2* quadVerts [[buffer(0)]],
    constant ASCIICell* cells [[buffer(1)]],
    constant FlowerUniforms& uniforms [[buffer(2)]]
) {
    // Calculate cell position
    uint col = instanceID % uniforms.columns;
    uint row = instanceID / uniforms.columns;
    
    // Cell size in NDC
    float2 cellSize = 2.0 / float2(uniforms.columns, uniforms.rows);
    
    // Cell origin (top-left in NDC)
    float2 origin = float2(-1.0, 1.0) + float2(float(col), -float(row)) * cellSize;
    
    // Vertex position within cell
    float2 pos = origin + quadVerts[vertexID] * cellSize;
    
    ASCIIVertexOut out;
    out.position = float4(pos, 0.0, 1.0);
    out.texCoord = quadVerts[vertexID];
    out.brightness = float(cells[instanceID].brightness) / 255.0;
    out.charIndex = cells[instanceID].character;
    
    return out;
}

fragment float4 asciiFragment(
    ASCIIVertexOut in [[stage_in]],
    texture2d<float, access::sample> fontTexture [[texture(0)]]
) {
    // Sample font texture for character
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    
    // Calculate UV for character in font atlas (16 chars in a row)
    float charU = float(in.charIndex % 16) / 16.0;
    float charV = float(in.charIndex / 16) / 16.0;
    float2 charUV = float2(charU, charV) + in.texCoord / 16.0;
    
    float4 charColor = fontTexture.sample(s, charUV);
    
    // Apply brightness as intensity
    float3 color = float3(in.brightness) * charColor.a;
    
    return float4(color, 1.0);
}

// MARK: - Simple ASCII Rendering (Without Font Texture)

fragment float4 asciiSimpleFragment(
    ASCIIVertexOut in [[stage_in]]
) {
    // Simple rendering: just output brightness as grayscale
    // The actual character rendering happens on CPU side
    float3 color = float3(in.brightness);
    return float4(color, 1.0);
}
