// main.swift
// MetalASCIIRunner - Standalone executable for ASCII art projects
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import SwiftUI
import MetalASCII

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        metalASCIILog("╔═══════════════════════════════════════════╗")
        metalASCIILog("║  MetalASCII Runner v\(MetalASCII.version)               ║")
        metalASCIILog("╠═══════════════════════════════════════════╣")
        metalASCIILog("║  Procedural ASCII Art Experiments         ║")
        metalASCIILog("║  Press 1-9 to switch scenes               ║")
        metalASCIILog("║  Press Cmd+Q to quit                      ║")
        metalASCIILog("╚═══════════════════════════════════════════╝")

        // Create window
        let windowRect = NSRect(x: 100, y: 100, width: 1400, height: 900)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window?.title = "MetalASCII"
        window?.backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0)
        window?.minSize = NSSize(width: 800, height: 500)

        // Use the SceneHostView with FlowerScene
        let contentView = NSHostingView(rootView:
                                            SceneHostView()
                                            .environment(\.devysTheme, ASCIITheme.terminal)
        )
        window?.contentView = contentView

        // Show window
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()

#else
metalASCIILog("MetalASCII requires macOS")
#endif
