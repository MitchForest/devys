// ToolCatalogTests.swift
// Tests for the tool catalog and parity with Zed's mappings.
//
// Copyright © 2026 Devys. All rights reserved.

import Testing
@testable import Agents

@Suite("ToolCatalog")
struct ToolCatalogTests {

    // MARK: - Parity Check

    @Test("All Zed Claude Code tool names are handled")
    func testZedParity() {
        let gaps = ToolCatalog.gapsVsZed
        #expect(gaps.isEmpty, "Tools in Zed but not in Devys: \(gaps.sorted())")
    }

    // MARK: - Claude Code Tool Mappings

    @Test("Read tool produces read kind with location")
    func testReadTool() {
        let info = ToolCatalog.info(
            forClaudeTool: "Read",
            input: ["file_path": "/src/main.swift", "offset": 10, "limit": 20]
        )
        #expect(info.kind == .read)
        #expect(info.title.contains("main.swift"))
        #expect(info.title.contains("11-30"))
        #expect(info.locations.count == 1)
        #expect(info.locations[0].path == "/src/main.swift")
        #expect(info.locations[0].line == 10)
    }

    @Test("Read tool with no offset")
    func testReadToolNoOffset() {
        let info = ToolCatalog.info(forClaudeTool: "Read", input: ["file_path": "/src/app.swift"])
        #expect(info.kind == .read)
        #expect(info.title == "Read /src/app.swift")
        #expect(info.locations.count == 1)
    }

    @Test("Write tool produces edit kind with location")
    func testWriteTool() {
        let info = ToolCatalog.info(forClaudeTool: "Write", input: ["file_path": "/src/new.swift"])
        #expect(info.kind == .edit)
        #expect(info.title == "Write /src/new.swift")
        #expect(info.locations.count == 1)
    }

    @Test("Edit tool produces edit kind with location")
    func testEditTool() {
        let info = ToolCatalog.info(
            forClaudeTool: "Edit",
            input: ["file_path": "/src/main.swift", "old_string": "foo", "new_string": "bar"]
        )
        #expect(info.kind == .edit)
        #expect(info.title == "Edit /src/main.swift")
        #expect(info.locations.count == 1)
    }

    @Test("Bash tool produces execute kind with command title")
    func testBashTool() {
        let info = ToolCatalog.info(forClaudeTool: "Bash", input: ["command": "swift build"])
        #expect(info.kind == .execute)
        #expect(info.title == "`swift build`")
        #expect(info.locations.isEmpty)
    }

    @Test("BashOutput tool produces execute kind")
    func testBashOutputTool() {
        let info = ToolCatalog.info(forClaudeTool: "BashOutput")
        #expect(info.kind == .execute)
        #expect(info.title == "Tail Logs")
    }

    @Test("KillShell tool produces execute kind")
    func testKillShellTool() {
        let info = ToolCatalog.info(forClaudeTool: "KillShell")
        #expect(info.kind == .execute)
        #expect(info.title == "Kill Process")
    }

    @Test("Glob tool produces search kind")
    func testGlobTool() {
        let info = ToolCatalog.info(
            forClaudeTool: "Glob",
            input: ["pattern": "**/*.swift", "path": "/src"]
        )
        #expect(info.kind == .search)
        #expect(info.title.contains("**/*.swift"))
    }

    @Test("Grep tool produces search kind")
    func testGrepTool() {
        let info = ToolCatalog.info(
            forClaudeTool: "Grep",
            input: ["pattern": "TODO", "path": "/src"]
        )
        #expect(info.kind == .search)
        #expect(info.title.contains("TODO"))
    }

    @Test("LS tool produces search kind")
    func testLSTool() {
        let info = ToolCatalog.info(forClaudeTool: "LS", input: ["path": "/src"])
        #expect(info.kind == .search)
        #expect(info.title.contains("/src"))
    }

    @Test("WebFetch tool produces fetch kind")
    func testWebFetchTool() {
        let info = ToolCatalog.info(
            forClaudeTool: "WebFetch",
            input: ["url": "https://example.com"]
        )
        #expect(info.kind == .fetch)
        #expect(info.title.contains("example.com"))
    }

    @Test("WebSearch tool produces fetch kind")
    func testWebSearchTool() {
        let info = ToolCatalog.info(
            forClaudeTool: "WebSearch",
            input: ["query": "Swift 6 concurrency"]
        )
        #expect(info.kind == .fetch)
        #expect(info.title.contains("Swift 6"))
    }

    @Test("Task tool produces think kind")
    func testTaskTool() {
        let info = ToolCatalog.info(
            forClaudeTool: "Task",
            input: ["description": "Analyze test coverage"]
        )
        #expect(info.kind == .think)
        #expect(info.title == "Analyze test coverage")
    }

    @Test("TodoWrite tool produces think kind")
    func testTodoWriteTool() {
        let info = ToolCatalog.info(forClaudeTool: "TodoWrite")
        #expect(info.kind == .think)
    }

    @Test("NotebookEdit tool produces edit kind")
    func testNotebookEditTool() {
        let info = ToolCatalog.info(
            forClaudeTool: "NotebookEdit",
            input: ["notebook_path": "/notebooks/analysis.ipynb"]
        )
        #expect(info.kind == .edit)
        #expect(info.locations.count == 1)
    }

    @Test("NotebookRead tool produces read kind")
    func testNotebookReadTool() {
        let info = ToolCatalog.info(
            forClaudeTool: "NotebookRead",
            input: ["notebook_path": "/notebooks/analysis.ipynb"]
        )
        #expect(info.kind == .read)
    }

    @Test("ExitPlanMode tool produces switchMode kind")
    func testExitPlanModeTool() {
        let info = ToolCatalog.info(forClaudeTool: "ExitPlanMode")
        #expect(info.kind == .switchMode)
        #expect(info.title == "Ready to code?")
    }

    @Test("Unknown tool produces other kind")
    func testUnknownTool() {
        let info = ToolCatalog.info(forClaudeTool: "SomeNewTool")
        #expect(info.kind == .other)
        #expect(info.title == "SomeNewTool")
    }

    // MARK: - Codex Item Type Mappings

    @Test("commandExecution produces execute kind")
    func testCodexCommand() {
        let info = ToolCatalog.info(
            forCodexItem: "commandExecution",
            payload: ["command": "npm test"]
        )
        #expect(info.kind == .execute)
        #expect(info.title.contains("npm test"))
    }

    @Test("fileChange produces edit kind")
    func testCodexFileChange() {
        let info = ToolCatalog.info(
            forCodexItem: "fileChange",
            payload: ["title": "Update main.swift"]
        )
        #expect(info.kind == .edit)
        #expect(info.title == "Update main.swift")
    }

    @Test("websearch produces fetch kind")
    func testCodexWebSearch() {
        let info = ToolCatalog.info(
            forCodexItem: "webSearch",
            payload: ["query": "Swift package manager"]
        )
        #expect(info.kind == .fetch)
    }

    @Test("plan produces think kind")
    func testCodexPlan() {
        let info = ToolCatalog.info(
            forCodexItem: "planImplementation",
            payload: ["title": "Test Plan"]
        )
        #expect(info.kind == .think)
        #expect(info.title == "Test Plan")
    }
}
