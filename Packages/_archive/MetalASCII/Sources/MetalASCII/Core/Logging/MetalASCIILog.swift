import Foundation

@inline(__always)
public func metalASCIILog(_ message: @autoclosure () -> String) {
    FileHandle.standardError.write(Data((message() + "\n").utf8))
}
