// WorkspaceTests.swift
// DevysCore Tests
//
// Copyright © 2026 Devys. All rights reserved.

import Testing
import Foundation
@testable import DevysCore

@Suite("Workspace Tests")
struct WorkspaceTests {
    @Test("Workspace initialization sets all properties")
    func workspaceInitialization() {
        let url = URL(fileURLWithPath: "/tmp/test-workspace")
        let workspace = Workspace(name: "Test", path: url)
        
        #expect(workspace.name == "Test")
        #expect(workspace.path == url)
        #expect(workspace.panelLayout == nil)
        #expect(workspace.lastOpened <= Date())
    }
    
    @Test("Workspace is Codable")
    func workspaceCodable() throws {
        let url = URL(fileURLWithPath: "/tmp/test-workspace")
        let original = Workspace(name: "Test", path: url)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Workspace.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.path == original.path)
    }
    
    @Test("Workspace equality checks all properties")
    func workspaceEquality() {
        let url = URL(fileURLWithPath: "/tmp/test-workspace")
        let workspace1 = Workspace(name: "Test", path: url)
        let workspace2 = workspace1  // Copy has same values
        
        #expect(workspace1 == workspace2)
        #expect(workspace1.id == workspace2.id)
    }
}

@Suite("PanelLayout Tests")
struct PanelLayoutTests {
    @Test("Default layout creates single pane")
    func defaultLayout() {
        let layout = PanelLayout.default
        
        if case .pane(let data) = layout.tree {
            #expect(data.tabs.isEmpty)
            #expect(data.selectedTabIndex == 0)
        } else {
            Issue.record("Default layout should be a single pane")
        }
    }
    
    @Test("PanelLayout is Codable")
    func panelLayoutCodable() throws {
        let layout = PanelLayout(tree: .split(
            orientation: .horizontal,
            children: [
                .pane(PaneData(id: UUID(), tabs: [], selectedTabIndex: 0)),
                .pane(PaneData(id: UUID(), tabs: [], selectedTabIndex: 0))
            ],
            ratios: [0.5, 0.5]
        ))
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(layout)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PanelLayout.self, from: data)
        
        #expect(decoded == layout)
    }
    
    @Test("TabData initialization")
    func tabDataInit() {
        let tab = TabData(title: "Test.swift", icon: "swift", isDirty: true)
        
        #expect(tab.title == "Test.swift")
        #expect(tab.icon == "swift")
        #expect(tab.isDirty == true)
        #expect(tab.filePath == nil)
    }
}
