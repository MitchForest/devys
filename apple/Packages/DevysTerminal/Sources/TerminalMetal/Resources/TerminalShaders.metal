#include <metal_stdlib>
using namespace metal;

struct TerminalCellData {
    float2 position;
    float2 size;
    float4 foregroundColor;
    float4 backgroundColor;
    float2 uvOrigin;
    float2 uvSize;
    uint flags;
    uint padding;
};

struct TerminalUniforms {
    float2 viewportSize;
};

struct TerminalVertexOut {
    float4 position [[position]];
    float4 foregroundColor;
    float4 backgroundColor;
    float2 texCoord;
    uint flags;
};

vertex TerminalVertexOut terminalCellVertexShader(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant TerminalCellData* cells [[buffer(0)]],
    constant TerminalUniforms& uniforms [[buffer(1)]]
) {
    TerminalCellData cell = cells[instanceID];
    float2 corners[4] = {
        float2(0, 0),
        float2(1, 0),
        float2(0, 1),
        float2(1, 1)
    };
    float2 corner = corners[vertexID];
    float2 pixelPos = cell.position + corner * cell.size;
    float2 ndc = (pixelPos / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;

    TerminalVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.foregroundColor = cell.foregroundColor;
    out.backgroundColor = cell.backgroundColor;
    out.texCoord = cell.uvOrigin + corner * cell.uvSize;
    out.flags = cell.flags;
    return out;
}

fragment float4 terminalCellFragmentShader(
    TerminalVertexOut in [[stage_in]],
    texture2d<float> glyphAtlas [[texture(0)]]
) {
    constexpr sampler texSampler(
        mag_filter::nearest,
        min_filter::nearest,
        address::clamp_to_edge
    );
    float alpha = glyphAtlas.sample(texSampler, in.texCoord).a;
    return mix(in.backgroundColor, in.foregroundColor, alpha);
}

struct TerminalOverlayVertex {
    float2 position;
    float4 color;
};

struct TerminalOverlayVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex TerminalOverlayVertexOut terminalOverlayVertexShader(
    uint vertexID [[vertex_id]],
    constant TerminalOverlayVertex* vertices [[buffer(0)]],
    constant TerminalUniforms& uniforms [[buffer(1)]]
) {
    TerminalOverlayVertex v = vertices[vertexID];
    float2 ndc = (v.position / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;

    TerminalOverlayVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = v.color;
    return out;
}

fragment float4 terminalOverlayFragmentShader(
    TerminalOverlayVertexOut in [[stage_in]]
) {
    return in.color;
}
