import CoreImage
import CoreImage.CIFilterBuiltins
public import SwiftUI

/// A QR code for a link, drawn crisp at any size.
public struct QRCode: View {
    let text: String
    let size: CGFloat

    public init(_ text: String, size: CGFloat = 200) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        if let image = Self.image(for: text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("QR code")
        }
    }

    /// One pixel per module; the view scales it without smoothing.
    static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
