import Foundation
import Network
import ServerProtocol

final class StreamSession: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let nextEvent: (StreamEventEnvelope.EventType, String) -> StreamEventEnvelope
    private let onClose: () -> Void
    private var timer: DispatchSourceTimer?
    private var isClosed = false

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        nextEvent: @escaping (StreamEventEnvelope.EventType, String) -> StreamEventEnvelope,
        onClose: @escaping () -> Void
    ) {
        self.connection = connection
        self.queue = queue
        self.nextEvent = nextEvent
        self.onClose = onClose
    }

    func start() {
        send(event: nextEvent(.welcome, "stream-connected"))

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.send(event: self.nextEvent(.heartbeat, "tick"))
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        close()
    }

    private func send(event: StreamEventEnvelope) {
        guard !isClosed else { return }

        do {
            var payload = try ServerJSONCoding.makeEncoder().encode(event)
            payload.append(0x0A)

            var chunk = Data("\(String(payload.count, radix: 16))\r\n".utf8)
            chunk.append(payload)
            chunk.append(Data("\r\n".utf8))

            connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.close()
                }
            })
        } catch {
            close()
        }
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true

        timer?.cancel()
        timer = nil

        connection.send(content: Data("0\r\n\r\n".utf8), completion: .contentProcessed { _ in
            self.connection.cancel()
            self.onClose()
        })
    }
}
