import AppFeatures
import Foundation

struct ReviewTriggerInboxStore: Sendable {
    private struct StoredRequest: Codable {
        let id: UUID
        let enqueuedAt: Date
        let request: ReviewTriggerRequest
    }

    private let inboxDirectoryURL: URL

    init(
        inboxDirectoryURL: URL = ReviewStorageLocations.reviewTriggerInboxDirectory()
    ) {
        self.inboxDirectoryURL = inboxDirectoryURL
    }

    func enqueue(_ request: ReviewTriggerRequest) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: inboxDirectoryURL,
            withIntermediateDirectories: true
        )

        let storedRequest = StoredRequest(
            id: UUID(),
            enqueuedAt: request.trigger.createdAt,
            request: request
        )
        let fileURL = inboxDirectoryURL.appendingPathComponent(
            "\(storedRequest.enqueuedAt.timeIntervalSince1970)-\(storedRequest.id.uuidString).json",
            isDirectory: false
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(storedRequest).write(to: fileURL, options: .atomic)
    }

    func drain() throws -> [ReviewTriggerRequest] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: inboxDirectoryURL.path) else {
            return []
        }

        let decoder = JSONDecoder()
        let fileURLs = try fileManager.contentsOfDirectory(
            at: inboxDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }

        var storedRequests: [(fileURL: URL, storedRequest: StoredRequest)] = []
        for fileURL in fileURLs {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            do {
                let data = try Data(contentsOf: fileURL)
                let storedRequest = try decoder.decode(StoredRequest.self, from: data)
                storedRequests.append((fileURL, storedRequest))
            } catch {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        let sortedRequests = storedRequests.sorted {
            if $0.storedRequest.enqueuedAt != $1.storedRequest.enqueuedAt {
                return $0.storedRequest.enqueuedAt < $1.storedRequest.enqueuedAt
            }
            return $0.storedRequest.id.uuidString < $1.storedRequest.id.uuidString
        }

        for entry in sortedRequests {
            try? fileManager.removeItem(at: entry.fileURL)
        }

        return sortedRequests.map(\.storedRequest.request)
    }
}

@MainActor
final class ReviewTriggerIngressBridge {
    private final class WakeObserverToken: @unchecked Sendable {
        let rawValue: NSObjectProtocol

        init(_ rawValue: NSObjectProtocol) {
            self.rawValue = rawValue
        }
    }

    private let inboxStore: ReviewTriggerInboxStore
    private let addWakeObserver:
        @MainActor @Sendable (@escaping @MainActor @Sendable () -> Void) -> NSObjectProtocol
    private let removeWakeObserver: @MainActor @Sendable (NSObjectProtocol) -> Void

    init(
        inboxStore: ReviewTriggerInboxStore,
        addWakeObserver: @escaping @MainActor @Sendable (
            @escaping @MainActor @Sendable () -> Void
        ) -> NSObjectProtocol,
        removeWakeObserver: @escaping @MainActor @Sendable (NSObjectProtocol) -> Void
    ) {
        self.inboxStore = inboxStore
        self.addWakeObserver = addWakeObserver
        self.removeWakeObserver = removeWakeObserver
    }

    func updates() -> AsyncStream<ReviewTriggerRequest> {
        AsyncStream { continuation in
            let observerToken = WakeObserverToken(addWakeObserver { [weak self] in
                self?.drainIntoStream(continuation)
            })

            drainIntoStream(continuation)

            continuation.onTermination = { [removeWakeObserver] _ in
                Task { @MainActor in
                    removeWakeObserver(observerToken.rawValue)
                }
            }
        }
    }

    private func drainIntoStream(
        _ continuation: AsyncStream<ReviewTriggerRequest>.Continuation
    ) {
        do {
            for request in try inboxStore.drain() {
                continuation.yield(request)
            }
        } catch {
            NSLog("Failed to drain review trigger inbox: \(error.localizedDescription)")
        }
    }
}
