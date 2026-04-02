import ChatCore
import Foundation
import Observation
import ServerProtocol

@MainActor
@Observable
public final class ConversationStore {
    public enum StreamState: Equatable, Sendable {
        case idle
        case connecting
        case streaming
        case failed(String)
    }

    public private(set) var activeSessionID: String?
    public private(set) var messages: [Message] = []
    public private(set) var streamState: StreamState = .idle
    public private(set) var nextCursor: StreamCursor?

    private let conversationActor: ConversationActor
    private let transportActor: TransportActor

    public init(
        conversationActor: ConversationActor = ConversationActor(),
        transportActor: TransportActor = TransportActor()
    ) {
        self.conversationActor = conversationActor
        self.transportActor = transportActor
    }

    public func activate(sessionID: String, history: [Message] = [], cursor: UInt64 = 0) async {
        activeSessionID = sessionID
        messages = await conversationActor.replaceMessages(history, sessionID: sessionID, cursor: cursor)
        nextCursor = await conversationActor.cursor(for: sessionID)
        streamState = .idle
    }

    public func beginStreaming() async {
        guard let activeSessionID else { return }
        let cursor = await transportActor.beginStreaming(sessionID: activeSessionID, resumeFrom: nextCursor)
        nextCursor = cursor
        streamState = .connecting
    }

    public func markStreaming() async {
        guard let activeSessionID else { return }
        await transportActor.markStreaming(sessionID: activeSessionID)
        streamState = .streaming
    }

    public func apply(event: ConversationEventEnvelope) async {
        do {
            let result = try await conversationActor.apply(event: event)
            nextCursor = await transportActor.apply(event: event)
            if result.didApply {
                messages = result.messages
            }
            if case .connecting = streamState {
                streamState = .streaming
            }
        } catch {
            guard let activeSessionID else { return }
            await transportActor.fail(sessionID: activeSessionID, message: error.localizedDescription)
            streamState = .failed(error.localizedDescription)
        }
    }

    public func endStreaming() async {
        guard let activeSessionID else { return }
        await transportActor.endStreaming(sessionID: activeSessionID)
        streamState = .idle
    }

    public func markStreamingFailure(_ message: String) async {
        guard let activeSessionID else { return }
        await transportActor.fail(sessionID: activeSessionID, message: message)
        streamState = .failed(message)
    }

    public func appendLocalUserMessage(_ text: String, messageID: String? = nil) async {
        guard let activeSessionID else { return }
        let message = Message(
            id: messageID ?? UUID().uuidString,
            sessionID: activeSessionID,
            role: .user,
            text: text,
            streamingState: .complete
        )
        messages = await conversationActor.upsertLocalMessage(message)
    }

    public func deactivate() async {
        if let activeSessionID {
            await transportActor.endStreaming(sessionID: activeSessionID)
        }
        activeSessionID = nil
        messages = []
        streamState = .idle
        nextCursor = nil
    }
}
