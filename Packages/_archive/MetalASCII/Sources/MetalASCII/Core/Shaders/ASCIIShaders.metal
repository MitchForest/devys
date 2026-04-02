// ASCIIShaders.metal
// DevysUI - Placeholder Metal shader file
//
// This file serves as a placeholder for Metal shader resources.
// ASCII art rendering is handled programmatically in Swift for better
// compatibility across different build configurations.
//
// Copyright © 2026 Devys. All rights reserved.

#include <metal_stdlib>
using namespace metal;

// MARK: - Placeholder Kernel
// This simple shader exists to ensure the Metal resource compiles.
// Actual ASCII art generation is done in Swift for maximum compatibility.

kernel void placeholderKernel(
    texture2d<float, access::write> output [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    output.write(float4(0, 0, 0, 1), gid);
}
