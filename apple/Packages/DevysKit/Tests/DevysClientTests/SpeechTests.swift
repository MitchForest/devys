import DevysClient
import Testing

@Suite("Speech endpoint")
struct SpeechEndpointTests {
    private func run(_ endpoint: inout SpeechEndpoint, seconds: Double, level: Double, text: String, mode: SpeechMode) -> SpeechEndpoint.Decision {
        var decision = SpeechEndpoint.Decision.listen
        var elapsed = 0.0
        while elapsed < seconds, decision == .listen {
            decision = endpoint.receive(level: level, duration: 0.1, text: text, mode: mode)
            elapsed += 0.1
        }
        return decision
    }

    @Test("Hands-free ends a turn after a settled pause")
    func handsFreeFinishes() {
        var endpoint = SpeechEndpoint()
        #expect(run(&endpoint, seconds: 1, level: 0.3, text: "what's blocking", mode: .handsFree) == .listen)
        #expect(run(&endpoint, seconds: 2, level: 0.001, text: "what's blocking launch", mode: .handsFree) == .finish)
    }

    @Test("New words restart the pause so late recognition isn't cut off")
    func lateWordsKeepListening() {
        var endpoint = SpeechEndpoint()
        _ = run(&endpoint, seconds: 1.0, level: 0.001, text: "send the", mode: .handsFree)
        #expect(endpoint.receive(level: 0.001, duration: 0.1, text: "send the inquiry", mode: .handsFree) == .listen)
    }

    @Test("Hands-free gives up after eight seconds of silence")
    func noSpeech() {
        var endpoint = SpeechEndpoint()
        #expect(run(&endpoint, seconds: 9, level: 0.001, text: "", mode: .handsFree) == .noSpeech)
    }

    @Test("Dictation only ends when you end it, or at the limit")
    func dictationIsManual() {
        var dictation = SpeechEndpoint()
        #expect(run(&dictation, seconds: 30, level: 0.001, text: "hello", mode: .dictation) == .listen)
        var long = SpeechEndpoint()
        #expect(run(&long, seconds: 301, level: 0.2, text: "hello", mode: .dictation) == .finish)
    }
}
