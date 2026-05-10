import SwiftUI
import UI

#if os(macOS)
import AppKit
#endif

struct TerminalComposerWaveformView: View {
    var level: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<28, id: \.self) { index in
                    Capsule()
                        .fill(Color.primary.opacity(0.34 + (barHeight(index: index, time: time) * 0.42)))
                        .frame(width: 3, height: 8 + (barHeight(index: index, time: time) * 22))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
            .accessibilityLabel("Dictation audio level")
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> Double {
        let phase = time * 7.5 + Double(index) * 0.48
        let wave = (sin(phase) + 1) * 0.5
        return min(max(0.18 + level * (0.30 + wave * 0.70), 0), 1)
    }
}

struct TerminalComposerPushToTalkBridge: View {
    var isComposerActive: Bool
    var isDictating: Bool
    var dictationKey: TerminalComposerDictationKey
    var onBegin: @MainActor () -> Void
    var onCommit: @MainActor () -> Void
    var onCancel: @MainActor () -> Void

    var body: some View {
        #if os(macOS)
        TerminalComposerMacPushToTalkBridge(
            isComposerActive: isComposerActive,
            isDictating: isDictating,
            dictationKey: dictationKey,
            onBegin: onBegin,
            onCommit: onCommit,
            onCancel: onCancel
        )
        .frame(width: 0, height: 0)
        #else
        EmptyView()
        #endif
    }
}

#if os(macOS)
private struct TerminalComposerMacPushToTalkBridge: NSViewRepresentable {
    var isComposerActive: Bool
    var isDictating: Bool
    var dictationKey: TerminalComposerDictationKey
    var onBegin: @MainActor () -> Void
    var onCommit: @MainActor () -> Void
    var onCancel: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var parent: TerminalComposerMacPushToTalkBridge
        private var monitor: Any?
        private var functionKeyIsDown = false

        init(_ parent: TerminalComposerMacPushToTalkBridge) {
            self.parent = parent
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard parent.isComposerActive else {
                functionKeyIsDown = false
                return event
            }

            if event.type == .keyDown, event.keyCode == 53, parent.isDictating {
                functionKeyIsDown = false
                parent.onCancel()
                return nil
            }

            guard event.type == .flagsChanged else { return event }
            let isFunctionPressed = event.modifierFlags.contains(parent.dictationKey.modifierFlag)

            if isFunctionPressed, !functionKeyIsDown {
                functionKeyIsDown = true
                parent.onBegin()
            } else if !isFunctionPressed, functionKeyIsDown {
                functionKeyIsDown = false
                parent.onCommit()
            }

            return event
        }
    }
}

private extension TerminalComposerDictationKey {
    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .function:
            .function
        case .control:
            .control
        case .option:
            .option
        }
    }
}
#endif
