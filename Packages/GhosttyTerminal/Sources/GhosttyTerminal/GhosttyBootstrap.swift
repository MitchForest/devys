import Foundation

#if canImport(GhosttyKit)
import GhosttyKit
#endif

public struct GhosttyBootstrapStatus: Equatable, Sendable {
    public let repositoryURL: String
    public let pinnedCommit: String
    public let ghosttyVersion: String
    public let minimumZigVersion: String
    public let sourceCheckoutExists: Bool
    public let artifactExists: Bool
    public let resourcesExist: Bool
    public let frameworkImportable: Bool

    public var shortCommit: String {
        String(pinnedCommit.prefix(12))
    }

    public var frameworkStateLabel: String {
        if frameworkImportable {
            return "linked"
        }

        return artifactExists ? "artifact_staged" : "artifact_missing"
    }

    public var sourceStateLabel: String {
        sourceCheckoutExists ? "checked_out" : "not_bootstrapped"
    }
}

public enum GhosttyBootstrap {
    public static let repositoryURL = "https://github.com/ghostty-org/ghostty.git"
    public static let pinnedCommit = "48d3e972d839999745368b156df396d9512fd17b"
    public static let ghosttyVersion = "1.3.2-dev"
    public static let minimumZigVersion = "0.15.2"

    public static let sourceCheckoutRelativePath = ".deps/ghostty-src"
    public static let artifactRelativePath = "Vendor/Ghostty/GhosttyKit.xcframework"
    public static let resourcesRelativePath = "Vendor/Ghostty/share/ghostty"

    public static var status: GhosttyBootstrapStatus {
        GhosttyBootstrapStatus(
            repositoryURL: repositoryURL,
            pinnedCommit: pinnedCommit,
            ghosttyVersion: ghosttyVersion,
            minimumZigVersion: minimumZigVersion,
            sourceCheckoutExists: FileManager.default.fileExists(atPath: sourceCheckoutPath),
            artifactExists: FileManager.default.fileExists(atPath: artifactPath),
            resourcesExist: FileManager.default.fileExists(atPath: resourcesPath),
            frameworkImportable: frameworkImportable
        )
    }

    private static let repoRootURL: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    private static var sourceCheckoutPath: String {
        repoRootURL.appendingPathComponent(sourceCheckoutRelativePath).path
    }

    private static var artifactPath: String {
        repoRootURL.appendingPathComponent(artifactRelativePath).path
    }

    private static var resourcesPath: String {
        repoRootURL.appendingPathComponent(resourcesRelativePath).path
    }

    #if canImport(GhosttyKit)
    private static let frameworkImportable = true
    #else
    private static let frameworkImportable = false
    #endif
}
