import ACPClientKit
import Foundation

let sharedTestDescriptor = ACPAgentDescriptor(
    kind: .codex,
    displayName: "ACP Test Adapter",
    executableName: "ACPClientKitTestAdapter"
)

func makeTestLaunchOptions(
    mode: String? = nil,
    requiredCapabilities: [String] = []
) -> ACPAdapterLaunchOptions {
    var environment = ProcessInfo.processInfo.environment
    if let mode {
        environment["ACP_TEST_MODE"] = mode
    } else {
        environment.removeValue(forKey: "ACP_TEST_MODE")
    }

    return ACPAdapterLaunchOptions(
        configuredExecutableURL: testAdapterExecutableURL(),
        environment: environment,
        requiredCapabilities: requiredCapabilities,
        clientInfo: ACPImplementationInfo(name: "ACPClientKitTests", version: "1.0")
    )
}

func testAdapterExecutableURL() -> URL {
    let fileManager = FileManager.default
    for directory in candidateProductsDirectories() {
        let candidate = directory.appending(path: "ACPClientKitTestAdapter", directoryHint: .notDirectory)
        if fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }

    return candidateProductsDirectories().first!
        .appending(path: "ACPClientKitTestAdapter", directoryHint: .notDirectory)
}

private func candidateProductsDirectories(filePath: StaticString = #filePath) -> [URL] {
    let fileURL = URL(fileURLWithPath: "\(filePath)")
    let packageRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    let buildRoot = packageRoot.appending(path: ".build", directoryHint: .isDirectory)
    var directories = [
        buildRoot.appending(path: "debug", directoryHint: .isDirectory),
        buildRoot.appending(path: "arm64-apple-macosx/debug", directoryHint: .isDirectory),
    ]

    if let builtProductsDirectory = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
        directories.insert(URL(fileURLWithPath: builtProductsDirectory, isDirectory: true), at: 0)
    }

    return directories
}
