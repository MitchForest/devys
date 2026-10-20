import CoreGraphics
import DevysCharacter
import DevysClient
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@Suite("Looks")
struct LooksTests {
    private func png(side: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.3, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("Looks decode from and encode to the server's JSON, the same shape the web uses")
    func serverShape() throws {
        let face = try JSONDecoder().decode(Look.self, from: Data(#"{"kind":"face","palette":"teal","shape":"hexagon","seed":3}"#.utf8))
        #expect(face == .face(AvatarSpec(palette: .teal, shape: .hexagon, seed: 3)))
        let emoji = try JSONDecoder().decode(Look.self, from: Data(#"{"kind":"emoji","emoji":"🦉","tint":"purple"}"#.utf8))
        #expect(emoji == .emoji("🦉", tint: "purple"))
        let photo = try JSONDecoder().decode(Look.self, from: Data(#"{"kind":"photo","version":"a1b2"}"#.utf8))
        #expect(photo == .photo(version: "a1b2"))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(face)) as? [String: AnyHashable]
        #expect(encoded == ["kind": "face", "palette": "teal", "shape": "hexagon", "seed": 3])
        let employee = try JSONDecoder().decode(
            Employee.self,
            from: Data(#"{"id":"e","name":"Ops","role":"Runs","paused":false,"model":"claude-opus-5-5","look":{"kind":"emoji","emoji":"🦉","tint":"blue"}}"#.utf8)
        )
        #expect(employee.look == .emoji("🦉", tint: "blue"))
    }

    @Test("Setting a look posts it, and a reset sends null so the server restores the default")
    func setsOnServer() async throws {
        let recorder = Recorder()
        let client = DevysHTTPClient { request in
            await recorder.record(request)
            return (Data(#"{"look":null}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let session = DeviceSession(server: URL(string: "https://devys.test")!, token: "tok")
        let target = LookTarget.employee(business: "b", employee: "e")
        try await client.setLook(session, path: target.path, look: nil)
        let reset = try #require(await recorder.requests.last)
        #expect(reset.url?.path() == "/api/businesses/b/employees/e/look")
        #expect(String(data: try #require(reset.httpBody), encoding: .utf8) == #"{"look":null}"#)
        try await client.uploadLookPhoto(session, path: LookTarget.business("b").path, jpeg: Data([1]))
        let upload = try #require(await recorder.requests.last)
        #expect(upload.httpMethod == "PUT")
        #expect(upload.url?.path() == "/api/businesses/b/look/photo")
    }

    @Test("Photos are downscaled to 512 pixels before upload; unreadable images are refused")
    func downscales() throws {
        let jpeg = try #require(ImageDownscaler.jpeg(from: try png(side: 2048), maxPixel: 512))
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 512)
        #expect(ImageDownscaler.jpeg(from: Data("not an image".utf8), maxPixel: 512) == nil)
    }

    @Test("A missing profile photo reads as none; uploads send JPEG")
    func profilePhoto() async throws {
        let recorder = Recorder()
        let missing = DevysHTTPClient { request in
            await recorder.record(request)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        let session = DeviceSession(server: URL(string: "https://devys.test")!, token: "tok")
        #expect(try await missing.profilePhoto(session) == nil)
        let accepting = DevysHTTPClient { request in
            await recorder.record(request)
            return (Data(#"{"saved":true}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        try await accepting.uploadProfilePhoto(session, jpeg: Data([1, 2, 3]))
        let upload = try #require(await recorder.requests.last)
        #expect(upload.httpMethod == "PUT")
        #expect(upload.value(forHTTPHeaderField: "content-type") == "image/jpeg")
        #expect(upload.url?.path() == "/api/profile/photo")
    }

    private actor Recorder {
        var requests: [URLRequest] = []
        func record(_ request: URLRequest) { requests.append(request) }
    }
}
