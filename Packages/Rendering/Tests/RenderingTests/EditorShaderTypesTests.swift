import Testing
import simd
@testable import Rendering

@Suite("EditorShaderTypes Tests")
struct EditorShaderTypesTests {
    @Test("Hex colors support short RGB input")
    func shortRGBHex() {
        let color = hexToLinearColor("#0F8")

        #expect(color.x == srgbToLinear(0))
        #expect(color.y == srgbToLinear(1))
        #expect(color.z == srgbToLinear(Float(0x88) / 255))
        #expect(color.w == 1)
    }

    @Test("Hex colors prefer embedded alpha when present")
    func rgbaHex() {
        let color = hexToLinearColor("#33669980", alpha: 1)

        #expect(color.x == srgbToLinear(Float(0x33) / 255))
        #expect(color.y == srgbToLinear(Float(0x66) / 255))
        #expect(color.z == srgbToLinear(Float(0x99) / 255))
        #expect(color.w == Float(0x80) / 255)
    }

    @Test("Editor cell GPU defaults are stable")
    func editorCellDefaults() {
        let cell = EditorCellGPU()

        #expect(cell.position == SIMD2<Float>.zero)
        #expect(cell.uvOrigin == SIMD2<Float>.zero)
        #expect(cell.uvSize == SIMD2<Float>.zero)
        #expect(cell.flags == 0)
        #expect(cell.padding == 0)
    }
}
