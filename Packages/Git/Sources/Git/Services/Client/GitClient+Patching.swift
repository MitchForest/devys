import Foundation

extension GitClient {
    func stagePatch(_ patch: String) async throws {
        try await applyPatch(patch, cached: true, reverse: false)
    }

    func unstagePatch(_ patch: String) async throws {
        try await applyPatch(patch, cached: true, reverse: true)
    }

    func discardPatch(_ patch: String) async throws {
        try await applyPatch(patch, cached: false, reverse: true)
    }
}
