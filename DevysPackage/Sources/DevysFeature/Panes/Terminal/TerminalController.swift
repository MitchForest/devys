import AppKit
import SwiftTerm

// MARK: - TerminalControllerDelegate

/// Protocol for terminal events.
public protocol TerminalControllerDelegate: AnyObject {
    /// Called when the terminal title changes (from shell escape sequence)
    func terminalTitleDidChange(_ title: String)

    /// Called when the current directory changes
    func terminalDirectoryDidChange(_ directory: URL?)

    /// Called when the running state changes (output activity detected)
    func terminalRunningStateDidChange(_ isRunning: Bool)
}

// MARK: - TerminalController

/// AppKit controller managing a SwiftTerm terminal.
///
/// ## Running State Detection
///
/// Uses output activity tracking to detect when AI agents are actively
/// producing output (running) vs waiting for input (idle).
///
/// The algorithm distinguishes AI streaming from user typing:
/// - AI streaming: large bursts of output (50+ bytes in 200ms)
/// - User typing: small bursts (1-5 bytes per keystroke)
///
/// When large bursts are detected → running (green)
/// When no output for 2 seconds → idle (gray)
public class TerminalController: NSViewController {
    // MARK: - Properties

    private var terminalView: ActivityTrackingTerminalView!
    private var state: TerminalState

    /// Delegate for terminal events
    public weak var delegate: TerminalControllerDelegate?

    // MARK: - Activity Detection Configuration

    /// Bytes needed to consider output "significant" (filters out typing echo)
    /// AI streaming produces 50-500+ bytes per chunk
    /// User typing produces 1-5 bytes per keystroke
    private let significantBytesThreshold: Int = 50

    /// Time window to accumulate output before evaluating (seconds)
    private let burstWindowDuration: TimeInterval = 0.2

    /// Time of no output before marking as idle (seconds)
    private let idleTimeoutDuration: TimeInterval = 2.0

    // MARK: - Activity Detection State

    /// Bytes received in current evaluation window
    private var bytesInCurrentWindow: Int = 0

    /// When the current evaluation window started
    private var windowStartTime: Date = Date()

    /// Timer to check for idle state
    private var idleCheckTimer: Timer?

    /// Last time we received any output
    private var lastOutputTime: Date = Date()

    /// Whether a command is currently running (producing significant output)
    public private(set) var isRunning: Bool = false {
        didSet {
            if oldValue != isRunning {
                delegate?.terminalRunningStateDidChange(isRunning)
            }
        }
    }

    // MARK: - Initialization

    public init(state: TerminalState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Lifecycle

    override public func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupTerminalView()
        setupContextMenu()
        startShellProcess()
        startIdleMonitoring()
    }

    override public func viewDidAppear() {
        super.viewDidAppear()
        focus()
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        terminalView.frame = view.bounds
    }

    override public func viewWillDisappear() {
        super.viewWillDisappear()
        idleCheckTimer?.invalidate()
    }

    // MARK: - Setup

    private func setupTerminalView() {
        terminalView = ActivityTrackingTerminalView(frame: view.bounds)
        terminalView.autoresizingMask = [.width, .height]
        terminalView.processDelegate = self
        terminalView.outputDelegate = self

        configureTerminalAppearance()
        terminalView.registerForDraggedTypes([.fileURL])

        view.addSubview(terminalView)
    }

    private func configureTerminalAppearance() {
        terminalView.configureNativeColors()

        let fontSize: CGFloat = 13
        if let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) as NSFont? {
            terminalView.font = font
        }
    }

    private func setupContextMenu() {
        let menu = NSMenu(title: "Terminal")

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyAction), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = .command
        copyItem.target = self
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(pasteAction), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = .command
        pasteItem.target = self
        menu.addItem(pasteItem)

        menu.addItem(NSMenuItem.separator())

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(selectAllAction), keyEquivalent: "a")
        selectAllItem.keyEquivalentModifierMask = .command
        selectAllItem.target = self
        menu.addItem(selectAllItem)

        let clearItem = NSMenuItem(title: "Clear", action: #selector(clearAction), keyEquivalent: "k")
        clearItem.keyEquivalentModifierMask = .command
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(NSMenuItem.separator())

        let interruptItem = NSMenuItem(title: "Send Interrupt (Ctrl+C)", action: #selector(interruptAction), keyEquivalent: "")
        interruptItem.target = self
        menu.addItem(interruptItem)

        let eofItem = NSMenuItem(title: "Send EOF (Ctrl+D)", action: #selector(eofAction), keyEquivalent: "")
        eofItem.target = self
        menu.addItem(eofItem)

        terminalView.menu = menu
    }

    // MARK: - Context Menu Actions

    @objc private func copyAction() { copySelection() }
    @objc private func pasteAction() { paste() }
    @objc private func selectAllAction() { selectAll() }
    @objc private func clearAction() { clear() }
    @objc private func interruptAction() { sendInterrupt() }
    @objc private func eofAction() { sendEOF() }

    private func startShellProcess() {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"

        let shellName = (state.shell as NSString).lastPathComponent

        terminalView.startProcess(
            executable: state.shell,
            args: ["-l"],
            environment: Array(env.map { "\($0.key)=\($0.value)" }),
            execName: shellName
        )

        let path = state.workingDirectory.path
        if FileManager.default.fileExists(atPath: path) {
            let escapedPath = TerminalState.escapePath(path)
            terminalView.send(txt: "cd \(escapedPath) && clear\n")
        }
    }

    // MARK: - Activity Detection

    /// Start monitoring for idle state
    private func startIdleMonitoring() {
        // Check every 500ms if we should transition to idle
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForIdleState()
            }
        }
    }

    /// Called when output is received from the terminal process
    private func handleOutputReceived(byteCount: Int) {
        let now = Date()
        lastOutputTime = now

        // Check if we should start a new evaluation window
        let windowAge = now.timeIntervalSince(windowStartTime)
        if windowAge >= burstWindowDuration {
            // Evaluate the previous window
            evaluateWindow()
            // Start new window
            windowStartTime = now
            bytesInCurrentWindow = byteCount
        } else {
            // Accumulate in current window
            bytesInCurrentWindow += byteCount
        }
    }

    /// Evaluate the accumulated output in the current window
    private func evaluateWindow() {
        if bytesInCurrentWindow >= significantBytesThreshold {
            // Significant output burst detected = AI is streaming
            isRunning = true
        }
        bytesInCurrentWindow = 0
    }

    /// Check if terminal has been idle long enough to mark as not running
    private func checkForIdleState() {
        let timeSinceLastOutput = Date().timeIntervalSince(lastOutputTime)
        if timeSinceLastOutput >= idleTimeoutDuration {
            isRunning = false
        }
    }

    // MARK: - Public API

    public func sendText(_ text: String) {
        terminalView.send(txt: text)
    }

    public func sendBytes(_ bytes: [UInt8]) {
        terminalView.send(bytes)
    }

    public func sendInterrupt() {
        terminalView.send([0x03])
    }

    public func sendEOF() {
        terminalView.send([0x04])
    }

    public func clear() {
        terminalView.send(txt: "clear\n")
    }

    public func copySelection() {
        if let selection = terminalView.getSelection(), !selection.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selection, forType: .string)
        }
    }

    public func paste() {
        if let text = NSPasteboard.general.string(forType: .string) {
            terminalView.send(txt: text)
        }
    }

    public func selectAll() {
        terminalView.selectAll(nil)
    }

    public func focus() {
        view.window?.makeFirstResponder(terminalView)
    }
}

// MARK: - OutputActivityDelegate

extension TerminalController: OutputActivityDelegate {
    nonisolated public func terminalDidReceiveOutput(byteCount: Int) {
        Task { @MainActor [weak self] in
            self?.handleOutputReceived(byteCount: byteCount)
        }
    }
}

// MARK: - LocalProcessTerminalViewDelegate

extension TerminalController: LocalProcessTerminalViewDelegate {
    nonisolated public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let dir = directory else { return }
        let url = URL(fileURLWithPath: dir)
        Task { @MainActor [weak self] in
            self?.state.workingDirectory = url
            self?.delegate?.terminalDirectoryDidChange(url)
        }
    }

    nonisolated public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Terminal handles sizing internally
    }

    nonisolated public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            self?.state.title = title
            self?.delegate?.terminalTitleDidChange(title)
        }
    }

    nonisolated public func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            self?.idleCheckTimer?.invalidate()
            self?.isRunning = false
        }
    }
}
