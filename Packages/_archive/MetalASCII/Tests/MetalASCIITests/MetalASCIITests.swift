// MetalASCIITests.swift
// MetalASCII - Tests for ASCII art rendering
//
// Copyright © 2026 Devys. All rights reserved.

import XCTest
@testable import MetalASCII

final class MetalASCIITests: XCTestCase {
    
    func testVersion() {
        XCTAssertEqual(MetalASCII.version, "1.0.0")
    }
    
    func testDitherModeShaderIndex() {
        XCTAssertEqual(DitherMode.none.shaderIndex, 0)
        XCTAssertEqual(DitherMode.bayer4x4.shaderIndex, 1)
        XCTAssertEqual(DitherMode.bayer8x8.shaderIndex, 2)
        XCTAssertEqual(DitherMode.floydSteinberg.shaderIndex, 3)
        XCTAssertEqual(DitherMode.blueNoise.shaderIndex, 4)
    }
}
