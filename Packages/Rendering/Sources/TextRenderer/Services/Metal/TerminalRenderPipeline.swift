import Foundation
import Metal
import MetalKit

@MainActor
public final class TerminalRenderPipeline {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let cellPipeline: MTLRenderPipelineState
    public let overlayPipeline: MTLRenderPipelineState

    public init(device: MTLDevice) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            throw EditorRenderError.failedToCreateCommandQueue
        }
        self.commandQueue = commandQueue

        let library = try Self.loadShaderLibrary(device: device)
        self.cellPipeline = try Self.createCellPipeline(device: device, library: library)
        self.overlayPipeline = try Self.createOverlayPipeline(device: device, library: library)
    }

    private static func loadShaderLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let library = device.makeDefaultLibrary() {
            return library
        }
        if let library = try? device.makeLibrary(source: embeddedShaderSource, options: nil) {
            return library
        }
        throw EditorRenderError.failedToLoadShaders
    }

    private static func createCellPipeline(
        device: MTLDevice,
        library: MTLLibrary
    ) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: "terminalCellVertexShader"),
              let fragmentFunction = library.makeFunction(name: "terminalCellFragmentShader") else {
            throw EditorRenderError.shaderFunctionNotFound("terminalCellVertexShader/terminalCellFragmentShader")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Terminal Cell Pipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func createOverlayPipeline(
        device: MTLDevice,
        library: MTLLibrary
    ) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: "terminalOverlayVertexShader"),
              let fragmentFunction = library.makeFunction(name: "terminalOverlayFragmentShader") else {
            throw EditorRenderError.shaderFunctionNotFound("terminalOverlayVertexShader/terminalOverlayFragmentShader")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Terminal Overlay Pipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static let embeddedShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct CellData {
        float2 position;
        float2 size;
        float4 foregroundColor;
        float4 backgroundColor;
        float2 uvOrigin;
        float2 uvSize;
        uint flags;
        uint padding;
    };

    struct Uniforms {
        float2 viewportSize;
    };

    struct VertexOut {
        float4 position [[position]];
        float4 foregroundColor;
        float4 backgroundColor;
        float2 texCoord;
        uint flags;
    };

    vertex VertexOut terminalCellVertexShader(
        uint vertexID [[vertex_id]],
        uint instanceID [[instance_id]],
        constant CellData* cells [[buffer(0)]],
        constant Uniforms& uniforms [[buffer(1)]]
    ) {
        CellData cell = cells[instanceID];

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

        VertexOut out;
        out.position = float4(ndc, 0.0, 1.0);
        out.foregroundColor = cell.foregroundColor;
        out.backgroundColor = cell.backgroundColor;
        out.texCoord = cell.uvOrigin + corner * cell.uvSize;
        out.flags = cell.flags;
        return out;
    }

    fragment float4 terminalCellFragmentShader(
        VertexOut in [[stage_in]],
        texture2d<float> glyphAtlas [[texture(0)]]
    ) {
        constexpr sampler texSampler(
            mag_filter::nearest,
            min_filter::nearest,
            address::clamp_to_edge
        );

        float4 glyphSample = glyphAtlas.sample(texSampler, in.texCoord);
        float alpha = glyphSample.a;
        float4 color = mix(in.backgroundColor, in.foregroundColor, alpha);
        return color;
    }

    struct OverlayVertex {
        float2 position;
        float4 color;
    };

    struct OverlayVertexOut {
        float4 position [[position]];
        float4 color;
    };

    vertex OverlayVertexOut terminalOverlayVertexShader(
        uint vertexID [[vertex_id]],
        constant OverlayVertex* vertices [[buffer(0)]],
        constant Uniforms& uniforms [[buffer(1)]]
    ) {
        OverlayVertex v = vertices[vertexID];
        float2 ndc = (v.position / uniforms.viewportSize) * 2.0 - 1.0;
        ndc.y = -ndc.y;

        OverlayVertexOut out;
        out.position = float4(ndc, 0.0, 1.0);
        out.color = v.color;
        return out;
    }

    fragment float4 terminalOverlayFragmentShader(
        OverlayVertexOut in [[stage_in]]
    ) {
        return in.color;
    }
    """
}
