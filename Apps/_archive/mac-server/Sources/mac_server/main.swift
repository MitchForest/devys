import Foundation

private func argumentValue(flag: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
        return nil
    }
    return args[index + 1]
}

let args = ProcessInfo.processInfo.arguments
let host = argumentValue(flag: "--host", in: args) ?? "0.0.0.0"
let portString = argumentValue(flag: "--port", in: args) ?? "8787"
let port = UInt16(portString) ?? 8787

do {
    let server = try HTTPServer(
        host: host,
        port: port,
        serverName: "devys-mac-server",
        version: "0.1.0"
    )
    server.start()
    server.runForever()
} catch {
    fputs("failed to start server: \(error)\n", stderr)
    exit(1)
}
