// ASCIIArtShaders.metal
// DevysUI - Shape-aware Metal shaders for image-to-ASCII art conversion
//
// Uses 9-region sampling and 5-directional weight matching for high-quality
// ASCII art that preserves edges and directional detail.
//
// Copyright © 2026 Devys. All rights reserved.

#include <metal_stdlib>
using namespace metal;

// MARK: - Structures

/// Uniforms passed from Swift
struct ASCIIUniforms {
    float2 viewportSize;        // Output size in pixels
    float2 imageSize;           // Source image size
    float2 cellSize;            // Character cell size (e.g., 8x16)
    float4 foregroundColor;     // Text color (from theme accent)
    float4 backgroundColor;     // Background color
    uint   invertBrightness;    // 0 = normal, 1 = inverted
    float  contrastBoost;       // 1.0 = normal, >1 = higher contrast
    float  gamma;               // Gamma correction (1.0 = linear)
    uint   charCount;           // Number of characters in weight table
};

/// Vertex output for full-screen quad
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Helper Functions

/// Sample brightness from source image using luminance formula
inline float sampleBrightness(
    texture2d<float, access::sample> image,
    float2 uv,
    float gamma
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 color = image.sample(s, uv);
    // Standard luminance coefficients (BT.601)
    float brightness = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
    // Apply gamma correction
    return pow(brightness, gamma);
}

/// Sample 9 regions within a cell and compute 5 directional weights
/// Uses 4 samples per region (2x2 grid) for accurate averaging = 36 samples total
/// Returns: [top, bottom, left, right, middle]
inline void sampleRegionWeights(
    texture2d<float, access::sample> image,
    float2 cellUVMin,
    float2 cellUVMax,
    float gamma,
    float contrast,
    bool invert,
    thread float* outWeights  // 5 floats
) {
    // Sample 9 regions (3x3 grid), with 4 samples per region (2x2)
    float regions[9];
    
    for (int ry = 0; ry < 3; ry++) {
        for (int rx = 0; rx < 3; rx++) {
            // Calculate region bounds within the cell
            float2 regionMin = float2(float(rx) / 3.0, float(ry) / 3.0);
            float2 regionMax = float2(float(rx + 1) / 3.0, float(ry + 1) / 3.0);
            
            // Sample 4 points within this region (2x2 grid) and average
            float regionBrightness = 0.0;
            for (int sy = 0; sy < 2; sy++) {
                for (int sx = 0; sx < 2; sx++) {
                    // Position within region: 0.25 and 0.75 for even distribution
                    float2 subPos = float2(
                        (float(sx) + 0.5) / 2.0,
                        (float(sy) + 0.5) / 2.0
                    );
                    float2 regionPos = mix(regionMin, regionMax, subPos);
                    float2 sampleUV = mix(cellUVMin, cellUVMax, regionPos);
                    
                    regionBrightness += sampleBrightness(image, sampleUV, gamma);
                }
            }
            regionBrightness /= 4.0;  // Average of 4 samples
            
            // Apply inversion
            if (invert) {
                regionBrightness = 1.0 - regionBrightness;
            }
            
            // Apply contrast
            regionBrightness = (regionBrightness - 0.5) * contrast + 0.5;
            regionBrightness = clamp(regionBrightness, 0.0f, 1.0f);
            
            regions[ry * 3 + rx] = regionBrightness;
        }
    }
    
    // Region layout:
    // [0][1][2]  TL  T  TR
    // [3][4][5]  L   M  R
    // [6][7][8]  BL  B  BR
    
    float tl = regions[0], t = regions[1], tr = regions[2];
    float l = regions[3], m = regions[4], r = regions[5];
    float bl = regions[6], b = regions[7], br = regions[8];
    
    // Compute 5 directional weights
    outWeights[0] = (tl + t + tr) / 3.0;   // top
    outWeights[1] = (bl + b + br) / 3.0;   // bottom
    outWeights[2] = (tl + l + bl) / 3.0;   // left
    outWeights[3] = (tr + r + br) / 3.0;   // right
    outWeights[4] = m;                      // middle
}

/// Find best matching character using L1 distance on 5 weights
inline int findBestCharacter(
    thread float* imageWeights,     // 5 floats from image
    constant float* charWeights,    // charCount * 5 floats
    constant int* charCodes,        // charCount ASCII codes
    uint charCount
) {
    int bestChar = 32; // Default to space
    float bestDistance = 999999.0;
    
    for (uint i = 0; i < charCount; i++) {
        // Calculate L1 distance
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

/// Sample from font texture atlas
/// Font texture is arranged with characters in ASCII order starting at 32 (space)
/// Grid: 16 columns, 6 rows (96 characters)
/// Cell size: 16x24 pixels
inline float sampleFontTexture(
    texture2d<float, access::sample> fontTexture,
    int asciiCode,
    float2 cellPos        // Position within cell (0-1)
) {
    // Map ASCII code to grid position (chars 32-126)
    int charIndex = asciiCode - 32;
    if (charIndex < 0) charIndex = 0;
    if (charIndex > 94) charIndex = 94;
    
    // Grid layout: 16 columns, 6 rows
    float2 charOffset = float2(
        float(charIndex % 16),
        float(charIndex / 16)
    );
    
    // Texture dimensions: 256x144 (16*16, 6*24)
    float2 gridSize = float2(16.0, 6.0);
    
    // Calculate UV in font texture
    float2 uv = (charOffset + cellPos) / gridSize;
    
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    return fontTexture.sample(s, uv).r;
}

// MARK: - Vertex Shader

/// Simple vertex shader for full-screen quad
vertex VertexOut asciiVertexShader(
    uint vertexID [[vertex_id]],
    constant float2 *vertices [[buffer(0)]]
) {
    VertexOut out;
    
    // Full-screen quad vertices (triangle strip)
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    
    return out;
}

// MARK: - Fragment Shader (Shape-Aware)

/// Shape-aware ASCII art fragment shader
/// Uses 9-region sampling and 5-weight character matching
fragment float4 asciiArtFragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> sourceImage [[texture(0)]],
    texture2d<float, access::sample> fontTexture [[texture(1)]],
    constant ASCIIUniforms& uniforms [[buffer(0)]],
    constant float* charWeights [[buffer(1)]],
    constant int* charCodes [[buffer(2)]]
) {
    // Current pixel position
    float2 pixelPos = in.texCoord * uniforms.viewportSize;
    
    // Calculate which cell we're in
    float2 cellIndex = floor(pixelPos / uniforms.cellSize);
    float2 cellPos = fract(pixelPos / uniforms.cellSize);
    
    // Calculate how many cells fit in viewport
    float2 cellCount = floor(uniforms.viewportSize / uniforms.cellSize);
    
    // Calculate cell bounds in UV space
    float2 cellUVMin = cellIndex / cellCount;
    float2 cellUVMax = (cellIndex + 1.0) / cellCount;
    
    // Aspect ratio correction for source image
    float imageAspect = uniforms.imageSize.x / uniforms.imageSize.y;
    float viewAspect = uniforms.viewportSize.x / uniforms.viewportSize.y;
    
    float2 uvOffset = float2(0.0);
    float2 uvScale = float2(1.0);
    
    if (imageAspect > viewAspect) {
        // Image is wider - letterbox top/bottom
        float scale = viewAspect / imageAspect;
        uvScale.y = scale;
        uvOffset.y = (1.0 - scale) * 0.5;
    } else {
        // Image is taller - pillarbox left/right
        float scale = imageAspect / viewAspect;
        uvScale.x = scale;
        uvOffset.x = (1.0 - scale) * 0.5;
    }
    
    // Transform cell bounds to image UV space
    float2 imageCellUVMin = (cellUVMin - uvOffset) / uvScale;
    float2 imageCellUVMax = (cellUVMax - uvOffset) / uvScale;
    
    // Check if cell center is outside image bounds (letterbox/pillarbox area)
    float2 cellCenter = (imageCellUVMin + imageCellUVMax) * 0.5;
    if (cellCenter.x < 0.0 || cellCenter.x > 1.0 || 
        cellCenter.y < 0.0 || cellCenter.y > 1.0) {
        return uniforms.backgroundColor;
    }
    
    // Clamp cell bounds to image
    imageCellUVMin = clamp(imageCellUVMin, float2(0.0), float2(1.0));
    imageCellUVMax = clamp(imageCellUVMax, float2(0.0), float2(1.0));
    
    // Sample 9 regions and compute 5 weights
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
    
    // Find best matching character
    int bestChar = findBestCharacter(
        imageWeights,
        charWeights,
        charCodes,
        uniforms.charCount
    );
    
    // Sample font texture for the matched character
    float charValue = sampleFontTexture(fontTexture, bestChar, cellPos);
    
    // Mix foreground and background based on character value
    return mix(uniforms.backgroundColor, uniforms.foregroundColor, charValue);
}

// MARK: - Legacy Fragment Shader (Brightness Only)

/// Legacy brightness-only fragment shader (kept for fallback)
// Legacy ASCII ramp (16 characters by density)
constant int LEGACY_ASCII_RAMP[16] = {
    ' ', '.', '\'', '`', '-', ':', ';', '=',
    '+', '*', 'x', 'o', 'O', '#', '%', '@'
};

fragment float4 asciiArtFragmentLegacy(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> sourceImage [[texture(0)]],
    texture2d<float, access::sample> fontTexture [[texture(1)]],
    constant ASCIIUniforms& uniforms [[buffer(0)]]
) {
    
    // Current pixel position
    float2 pixelPos = in.texCoord * uniforms.viewportSize;
    
    // Calculate which cell we're in
    float2 cellIndex = floor(pixelPos / uniforms.cellSize);
    float2 cellPos = fract(pixelPos / uniforms.cellSize);
    
    // Calculate how many cells fit in viewport
    float2 cellCount = floor(uniforms.viewportSize / uniforms.cellSize);
    
    // Calculate source image UV for this cell (centered)
    float2 sourceUV = (cellIndex + 0.5) / cellCount;
    
    // Aspect ratio correction
    float imageAspect = uniforms.imageSize.x / uniforms.imageSize.y;
    float viewAspect = uniforms.viewportSize.x / uniforms.viewportSize.y;
    
    if (imageAspect > viewAspect) {
        float scale = viewAspect / imageAspect;
        sourceUV.y = (sourceUV.y - 0.5) / scale + 0.5;
    } else {
        float scale = imageAspect / viewAspect;
        sourceUV.x = (sourceUV.x - 0.5) / scale + 0.5;
    }
    
    // Check if outside image bounds
    if (sourceUV.x < 0.0 || sourceUV.x > 1.0 || 
        sourceUV.y < 0.0 || sourceUV.y > 1.0) {
        return uniforms.backgroundColor;
    }
    
    // Sample brightness
    float brightness = sampleBrightness(sourceImage, sourceUV, uniforms.gamma);
    
    // Apply inversion and contrast
    if (uniforms.invertBrightness != 0) {
        brightness = 1.0 - brightness;
    }
    brightness = (brightness - 0.5) * uniforms.contrastBoost + 0.5;
    brightness = clamp(brightness, 0.0f, 1.0f);
    
    // Map to character
    int charIndex = clamp(int(brightness * 15.0), 0, 15);
    int asciiChar = LEGACY_ASCII_RAMP[charIndex];
    
    // Sample font texture
    float charValue = sampleFontTexture(fontTexture, asciiChar, cellPos);
    
    return mix(uniforms.backgroundColor, uniforms.foregroundColor, charValue);
}

// MARK: - Compute Shader (Grid Output)

/// Compute shader that outputs character indices for CPU text rendering
kernel void computeASCIIGrid(
    texture2d<float, access::sample> sourceImage [[texture(0)]],
    device int *charGrid [[buffer(0)]],
    constant ASCIIUniforms& uniforms [[buffer(1)]],
    constant float* charWeights [[buffer(2)]],
    constant int* charCodes [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Grid dimensions
    uint2 gridSize = uint2(
        uint(uniforms.viewportSize.x / uniforms.cellSize.x),
        uint(uniforms.viewportSize.y / uniforms.cellSize.y)
    );
    
    if (gid.x >= gridSize.x || gid.y >= gridSize.y) return;
    
    // Calculate cell bounds in UV space
    float2 cellCount = float2(gridSize);
    float2 cellUVMin = float2(gid) / cellCount;
    float2 cellUVMax = (float2(gid) + 1.0) / cellCount;
    
    // Aspect ratio correction
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
    
    // Transform to image UV space
    float2 imageCellUVMin = (cellUVMin - uvOffset) / uvScale;
    float2 imageCellUVMax = (cellUVMax - uvOffset) / uvScale;
    float2 cellCenter = (imageCellUVMin + imageCellUVMax) * 0.5;
    
    int result;
    if (cellCenter.x < 0.0 || cellCenter.x > 1.0 || 
        cellCenter.y < 0.0 || cellCenter.y > 1.0) {
        result = 32; // Space for out-of-bounds
    } else {
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
        
        result = findBestCharacter(
            imageWeights,
            charWeights,
            charCodes,
            uniforms.charCount
        );
    }
    
    // Store result
    uint gridIndex = gid.y * gridSize.x + gid.x;
    charGrid[gridIndex] = result;
}
