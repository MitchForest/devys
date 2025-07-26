#!/bin/bash

# Create placeholder icons for Tauri
# These are simple colored squares - replace with real icons later

# Create icon directory if it doesn't exist
mkdir -p icons

# Use ImageMagick to create icons if available, otherwise use a simple method
if command -v convert &> /dev/null; then
    echo "Creating icons with ImageMagick..."
    convert -size 32x32 xc:#4A90E2 32x32.png
    convert -size 128x128 xc:#4A90E2 128x128.png
    convert -size 256x256 xc:#4A90E2 icon.png
    
    # Create ico file for Windows
    convert 32x32.png 128x128.png 256x256.png icon.ico
    
    # Create icns for macOS (simplified)
    cp icon.png icon.icns
else
    echo "ImageMagick not found. Creating placeholder files..."
    
    # Create minimal PNG files (1x1 pixel, will need to be replaced)
    # This is a base64 encoded 1x1 blue PNG
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" | base64 -d > 32x32.png
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" | base64 -d > 128x128.png
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" | base64 -d > icon.png
    
    # Create dummy ico and icns files
    cp icon.png icon.ico
    cp icon.png icon.icns
fi

echo "Icon files created:"
ls -la *.png *.ico *.icns 2>/dev/null || true