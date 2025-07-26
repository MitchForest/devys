#!/usr/bin/env node

// Simple script to generate PNG icons from SVG
// Run: bun generate-icons.js

import { writeFileSync } from 'fs';
import { join } from 'path';

const sizes = [32, 128, 256, 512, 1024];

// Create a simple circle icon with <devys/> text
function createIcon(size) {
  const scale = size / 512;
  const fontSize = Math.floor(72 * scale);
  const strokeWidth = Math.floor(4 * scale);
  
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" fill="none" xmlns="http://www.w3.org/2000/svg">
  <!-- Background circle -->
  <circle cx="${size/2}" cy="${size/2}" r="${size/2 - strokeWidth}" fill="#1F2428" stroke="#2D333C" stroke-width="${strokeWidth}"/>
  
  <!-- Text -->
  <text x="${size/2}" y="${size/2 + fontSize/3}" font-family="'SF Mono', Monaco, monospace" font-size="${fontSize}" font-weight="400" text-anchor="middle" fill="#BFBFBF">
    &lt;devys/&gt;
  </text>
</svg>`;
}

// Generate SVG files for each size
sizes.forEach(size => {
  const svg = createIcon(size);
  const filename = size === 256 ? 'icon.svg' : `icon-${size}.svg`;
  writeFileSync(join(import.meta.dir, filename), svg);
  console.log(`Generated ${filename}`);
});

console.log('\nNow you need to convert these SVGs to PNG format.');
console.log('On macOS, you can use a tool like:');
console.log('- Inkscape: inkscape -w SIZE -h SIZE icon.svg -o icon.png');
console.log('- rsvg-convert: rsvg-convert -w SIZE -h SIZE icon.svg -o icon.png');
console.log('- Online converter: https://cloudconvert.com/svg-to-png');