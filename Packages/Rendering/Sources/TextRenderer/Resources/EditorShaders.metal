// EditorShaders.metal
// DevysTextRenderer - Shared Metal text rendering
//
// Vertex and fragment shaders for text rendering.

#include <metal_stdlib>
using namespace metal;

// MARK: - Structures

/// Per-character data from CPU
struct CellData {
    float2 position;        // Pixel position
    float4 foregroundColor; // Text color (linear RGBA)
    float4 backgroundColor; // Background color (linear RGBA)
    float2 uvOrigin;        // Glyph atlas UV origin
    float2 uvSize;          // Glyph atlas UV size
    uint flags;             // Bold, italic, etc.
    uint padding;           // Alignment
};

/// Per-frame uniforms
struct Uniforms {
    float2 viewportSize;    // Viewport in pixels
    float2 cellSize;        // Cell size in pixels
    float2 atlasSize;       // Glyph atlas size in pixels
    float time;             // Animation time
    float cursorBlinkRate;  // Cursor blink rate (Hz)
};

/// Vertex output
struct VertexOut {
    float4 position [[position]];
    float4 foregroundColor;
    float4 backgroundColor;
    float2 texCoord;
    uint flags;
};

// MARK: - Cell Vertex Shader

/// Renders text cells using instanced drawing
/// Each cell is a quad (4 vertices as triangle strip)
vertex VertexOut editorCellVertexShader(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant CellData* cells [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    CellData cell = cells[instanceID];
    
    // Quad corners for triangle strip
    float2 corners[4] = {
        float2(0, 0),  // Top-left
        float2(1, 0),  // Top-right
        float2(0, 1),  // Bottom-left
        float2(1, 1)   // Bottom-right
    };
    
    float2 corner = corners[vertexID];
    
    // Position in pixels
    float2 pixelPos = cell.position + corner * uniforms.cellSize;
    
    // Convert to NDC (-1 to 1)
    float2 ndc = (pixelPos / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y for Metal coordinate system
    
    // UV coordinates in atlas
    float2 uv = cell.uvOrigin + corner * cell.uvSize;
    
    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.foregroundColor = cell.foregroundColor;
    out.backgroundColor = cell.backgroundColor;
    out.texCoord = uv;
    out.flags = cell.flags;
    return out;
}

// MARK: - Cell Fragment Shader

/// Renders text by sampling glyph alpha and blending colors
fragment float4 editorCellFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> glyphAtlas [[texture(0)]]
) {
    constexpr sampler texSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );
    
    // Sample glyph alpha from atlas
    float4 glyphSample = glyphAtlas.sample(texSampler, in.texCoord);
    float alpha = glyphSample.a;
    
    // Blend foreground over background
    float4 color = mix(in.backgroundColor, in.foregroundColor, alpha);
    
    // Handle dim flag (bit 4)
    if (in.flags & 0x10) {
        color.rgb *= 0.6;
    }
    
    return color;
}

// MARK: - Overlay Vertex Shader

/// Vertex data for overlays
struct OverlayVertex {
    float2 position;
    float4 color;
};

struct OverlayVertexOut {
    float4 position [[position]];
    float4 color;
};

/// Renders overlays (cursor, selection) as colored quads
vertex OverlayVertexOut editorOverlayVertexShader(
    uint vertexID [[vertex_id]],
    constant OverlayVertex* vertices [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    OverlayVertex v = vertices[vertexID];
    
    // Convert to NDC
    float2 ndc = (v.position / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    
    OverlayVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = v.color;
    return out;
}

/// Simple color output for overlays
fragment float4 editorOverlayFragmentShader(
    OverlayVertexOut in [[stage_in]]
) {
    return in.color;
}

// MARK: - Background Shader

/// Renders solid background for editor
vertex float4 editorBackgroundVertexShader(
    uint vertexID [[vertex_id]],
    constant float2* positions [[buffer(0)]]
) {
    return float4(positions[vertexID], 0.0, 1.0);
}

fragment float4 editorBackgroundFragmentShader(
    float4 position [[stage_in]],
    constant float4& color [[buffer(0)]]
) {
    return color;
}
