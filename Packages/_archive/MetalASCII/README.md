# MetalASCII

GPU-accelerated ASCII art rendering with dithering and animation.

## Overview

MetalASCII is a standalone Swift package for creating beautiful ASCII art visualizations using Metal. It provides infrastructure for multiple ASCII art "experiments" or "scenes" that can be run independently from the main Devys application.

## Features

- **GPU-Accelerated Rendering**: Uses Metal compute and render pipelines
- **Dithering Support**: Bayer 4x4, 8x8, and more dithering algorithms
- **Procedural Scenes**: Generate ASCII art from mathematical functions
- **Image-to-ASCII**: Convert images to ASCII art with shape-aware matching
- **60fps Animation**: Smooth real-time animation support
- **Modular Architecture**: Easy to add new scenes/experiments

## Running

```bash
# From the MetalASCII package directory
swift run ascii-runner
```

This opens a window with the scene viewer. Use the controls at the bottom to:
- Switch between scenes (Image, Flower, Gradient)
- Change dithering mode (None, 4x4, 8x8 Bayer)
- Adjust scene-specific parameters

## Available Scenes

### Particle Scene (Default)
Ethereal particle cloud with noise-based flow field. Features:
- GPU-accelerated simulation with 20,000+ particles
- Simplex noise flow field for organic movement
- Spiral motion with turbulence
- Density-based brightness accumulation
- Adjustable particle count, turbulence, and speed

### Flower Scene
Procedural rose-curve flower with wind animation. Features:
- Real-time simplex noise wind displacement
- Adjustable petal count (3-12)
- Wind strength control
- Metal compute shader for GPU acceleration

### Gradient Scene
Animated gradient patterns for testing. Features:
- Multiple gradient types (H, V, Radial, Diagonal, Wave)
- Wave modulation
- Good for testing dithering algorithms

## Architecture

```
MetalASCII/
├── Core/
│   ├── Engine/
│   │   ├── ASCIIEngine.swift      # Main rendering engine
│   │   ├── DitherEngine.swift     # Dithering algorithms
│   │   └── FontAtlas.swift        # Character texture management
│   ├── Scene/
│   │   ├── Scene.swift            # ASCIIScene protocol
│   │   └── SceneHostView.swift    # SwiftUI scene host
│   ├── Shaders/
│   │   ├── FlowerShaders.metal    # Procedural flower
│   │   ├── ASCIIArtShaders.metal  # Image-to-ASCII
│   │   └── ...
│   ├── Rendering/                 # Image-to-ASCII pipeline
│   ├── Effects/                   # Welcome effects
│   └── UI/                        # Terminal UI components
├── Projects/
│   ├── Flower/                    # Procedural flower scene
│   │   └── FlowerScene.swift
│   └── Gradient/                  # Gradient test scene
│       └── GradientScene.swift
└── Runner/
    └── main.swift                 # Standalone executable
```

## Creating a New Scene

1. Create a new folder under `Projects/`:
```swift
// Projects/MyScene/MyScene.swift
public final class MyScene: ASCIIScene {
    public let name = "MyScene"
    public let description = "My custom ASCII scene"
    
    public private(set) var asciiOutput: [[Character]] = []
    public private(set) var brightnessOutput: [[Float]] = []
    
    public required init(device: MTLDevice) throws {
        // Initialize Metal resources
    }
    
    public func resize(to size: CGSize) {
        // Handle resize
    }
    
    public func update(deltaTime: Float) {
        // Update animation state
        // Generate ASCII output
    }
    
    public func render(commandBuffer: MTLCommandBuffer, 
                       renderPassDescriptor: MTLRenderPassDescriptor) {
        // GPU rendering (optional - can do CPU-only)
    }
}
```

2. Add to `SceneType` enum in `SceneHostView.swift`:
```swift
public enum SceneType: String, CaseIterable {
    case flower = "Flower"
    case gradient = "Gradient"
    case myScene = "MyScene"  // Add here
}
```

3. Add to `SceneManager.switchScene()`:
```swift
case .myScene:
    if myScene == nil {
        myScene = try MyScene(device: device)
    }
```

## Dithering

The package supports multiple dithering modes:

- **None**: Direct brightness mapping
- **Bayer 4x4**: Subtle ordered dithering
- **Bayer 8x8**: Smoother gradients with larger pattern
- **Floyd-Steinberg**: Error diffusion (planned)
- **Blue Noise**: Organic feel (planned)

Use `DitherEngine.shared.applyDither()` for CPU dithering, or include the dithering in your Metal shaders.

## Character Mapping

ASCII characters are mapped by visual density using a 5-weight system:
- Top, Bottom, Left, Right, Middle region weights
- Best character is found by L1 distance matching
- Standard ramp: ` .,:;=+*xoO#%@MW`

Use `ASCIICharacterRamp.characterForBrightness()` for simple mapping, or `FontAtlas` for GPU-based rendering.

## Dependencies

- macOS 14.0+
- Swift 6.0
- Metal framework

## License

Proprietary - All rights reserved.
