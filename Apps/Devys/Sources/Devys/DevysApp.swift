// DevysApp.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import AppKit

/// App delegate to handle activation when running from a Swift Package
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activate the app and bring it to the foreground
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Default to light mode (aqua)
        NSApp.appearance = NSAppearance(named: .aqua)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct DevysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    // TODO: Implement new tab
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("New Window") {
                    // TODO: Implement new window
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            SidebarCommands()
        }
    }
}
