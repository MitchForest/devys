import AppKit
import SwiftTerm

/// Protocol for receiving output activity notifications
public protocol OutputActivityDelegate: AnyObject {
    /// Called when output is received from the terminal process
    func terminalDidReceiveOutput(byteCount: Int)
}

/// Custom LocalProcessTerminalView that tracks output activity.
///
/// This subclass intercepts `dataReceived` to notify when the process
/// produces output, enabling detection of "running" vs "idle" states
/// for AI agents and other long-running processes.
public class ActivityTrackingTerminalView: LocalProcessTerminalView {
    /// Delegate for output activity notifications
    public weak var outputDelegate: OutputActivityDelegate?

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    /// Intercept data from the process to track activity
    public override func dataReceived(slice: ArraySlice<UInt8>) {
        // Let the parent handle normal terminal processing
        super.dataReceived(slice: slice)

        // Notify our delegate about output activity
        outputDelegate?.terminalDidReceiveOutput(byteCount: slice.count)
    }
}
