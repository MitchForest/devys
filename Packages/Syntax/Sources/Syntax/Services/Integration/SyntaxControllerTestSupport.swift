import Foundation

actor SyntaxControllerTestSupport {
    static let shared = SyntaxControllerTestSupport()

    private var artificialHighlightDelayNanoseconds: UInt64?

    // periphery:ignore - deterministic test hook used from package tests only
    static func setArtificialHighlightDelay(nanoseconds: UInt64?) async {
        await shared.setArtificialHighlightDelay(nanoseconds: nanoseconds)
    }

    static func configuredArtificialHighlightDelay() async -> UInt64? {
        await shared.artificialHighlightDelayNanoseconds
    }

    // periphery:ignore - deterministic test hook used from package tests only
    private func setArtificialHighlightDelay(nanoseconds: UInt64?) {
        artificialHighlightDelayNanoseconds = nanoseconds
    }
}
