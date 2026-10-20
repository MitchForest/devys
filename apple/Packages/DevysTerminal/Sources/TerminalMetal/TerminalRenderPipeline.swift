// TerminalRenderPipeline.swift
// Devys - Metal pipeline states for the terminal cell grid and the
// selection/cursor overlay. Host views (DevysPackage) own the MTKView,
// its drive mode, and scale sourcing; they draw with these pipelines
// against a bgra8Unorm_srgb drawable.

internal import Foundation
public import Metal

public enum TerminalRenderError: Error {
    case failedToCreateCommandQueue
    case failedToLoadShaders
    case shaderFunctionNotFound(String)
}

@MainActor
public final class TerminalRenderPipeline {
    public let device: any MTLDevice
    public let commandQueue: any MTLCommandQueue
    public let cellPipeline: any MTLRenderPipelineState
    public let overlayPipeline: any MTLRenderPipelineState

    public init(device: any MTLDevice) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            throw TerminalRenderError.failedToCreateCommandQueue
        }
        self.commandQueue = commandQueue

        let library = try Self.loadShaderLibrary(device: device)
        self.cellPipeline = try Self.createCellPipeline(device: device, library: library)
        self.overlayPipeline = try Self.createOverlayPipeline(device: device, library: library)
    }

    // SwiftPM compiles Resources/TerminalShaders.metal into the target's
    // resource bundle metallib, so the default library must be resolved
    // against Bundle.module (the process default library is the app's).
    // The embedded source is the fallback for hosts whose toolchain did
    // not produce a metallib for the resource bundle.
    private static func loadShaderLibrary(device: any MTLDevice) throws -> any MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: .module) {
            return library
        }
        if let library = embeddedShaderLibraryOrNil(device: device) {
            return library
        }
        throw TerminalRenderError.failedToLoadShaders
    }

    private static func embeddedShaderLibraryOrNil(device: any MTLDevice) -> (any MTLLibrary)? {
        do {
            return try device.makeLibrary(source: embeddedShaderSource, options: nil)
        } catch {
            return nil
        }
    }

    private static func createCellPipeline(
        device: any MTLDevice,
        library: any MTLLibrary
    ) throws -> any MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: "terminalCellVertexShader"),
              let fragmentFunction = library.makeFunction(name: "terminalCellFragmentShader") else {
            throw TerminalRenderError.shaderFunctionNotFound("terminalCellVertexShader/terminalCellFragmentShader")
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
        device: any MTLDevice,
        library: any MTLLibrary
    ) throws -> any MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: "terminalOverlayVertexShader"),
              let fragmentFunction = library.makeFunction(name: "terminalOverlayFragmentShader") else {
            throw TerminalRenderError.shaderFunctionNotFound(
                "terminalOverlayVertexShader/terminalOverlayFragmentShader"
            )
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

    // Mirrors Resources/TerminalShaders.metal - keep the two in sync.
    private static let embeddedShaderSource = """
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
    """
}
