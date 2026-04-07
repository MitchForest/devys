// RepositoryLaunchPlannerTests.swift
// DevysCore Tests

import Foundation
import Testing
@testable import Workspace

@Suite("Repository launch planner tests")
struct RepositoryLaunchPlannerTests {
    @Test("Claude launcher resolution includes model, effort, permissions, and extra arguments")
    func resolveClaudeLauncher() throws {
        let launcher = LauncherTemplate(
            executable: "claude",
            model: "sonnet",
            reasoningLevel: "high",
            dangerousPermissions: true,
            extraArguments: ["--verbose"],
            executionBehavior: .stageInTerminal
        )

        let resolved = try RepositoryLaunchPlanner.resolveLauncher(launcher, kind: .claude)

        #expect(resolved.command == "claude --model sonnet --effort high --dangerously-skip-permissions --verbose")
        #expect(resolved.executionBehavior == .stageInTerminal)
    }

    @Test("Codex launcher resolution includes model, reasoning effort, and dangerous mode")
    func resolveCodexLauncher() throws {
        let launcher = LauncherTemplate(
            executable: "codex",
            model: "gpt-5-codex",
            reasoningLevel: "xhigh",
            dangerousPermissions: true,
            extraArguments: ["--search"]
        )

        let resolved = try RepositoryLaunchPlanner.resolveLauncher(launcher, kind: .codex)

        #expect(
            resolved.command
                == "codex -m gpt-5-codex -c model_reasoning_effort=\"xhigh\" --dangerously-bypass-approvals-and-sandbox --search"
        )
        #expect(resolved.executionBehavior == .runImmediately)
    }

    @Test(arguments: [
        (BuiltInLauncherKind.claude, "cc", "claude"),
        (BuiltInLauncherKind.codex, "cx", "codex")
    ])
    func resolveLegacyLauncherShorthand(
        kind: BuiltInLauncherKind,
        executable: String,
        expectedExecutable: String
    ) throws {
        let launcher = LauncherTemplate(executable: executable)

        let resolved = try RepositoryLaunchPlanner.resolveLauncher(launcher, kind: kind)

        #expect(resolved.command == expectedExecutable)
    }

    @Test("Default startup profile resolution preserves step order and workspace-relative cwd")
    func resolveDefaultStartupProfile() throws {
        let workspaceRoot = URL(fileURLWithPath: "/tmp/devys/repo")
        let webStep = StartupProfileStep(
            displayName: "Web",
            workingDirectory: "apps/web",
            command: "pnpm dev",
            environment: ["PORT": "3000"],
            launchMode: .newTab
        )
        let apiStep = StartupProfileStep(
            displayName: "API",
            workingDirectory: "apps/api",
            command: "pnpm dev",
            environment: ["PORT": "4000"],
            launchMode: .split
        )
        let workerStep = StartupProfileStep(
            displayName: "Worker",
            command: "pnpm worker",
            launchMode: .backgroundManagedProcess
        )
        let profile = StartupProfile(
            displayName: "Full Stack",
            description: "Launch the local stack",
            steps: [webStep, apiStep, workerStep]
        )
        let settings = RepositorySettings(
            startupProfiles: [profile],
            defaultStartupProfileID: profile.id
        )

        let resolved = try RepositoryLaunchPlanner.resolveDefaultStartupProfile(
            in: settings,
            workspaceRoot: workspaceRoot
        )

        #expect(resolved.profile.id == profile.id)
        #expect(resolved.steps.map(\.displayName) == ["Web", "API", "Worker"])
        #expect(
            resolved.steps[0].workingDirectory
                == workspaceRoot.appendingPathComponent("apps/web", isDirectory: true).standardizedFileURL
        )
        #expect(resolved.steps[1].launchMode == .split)
        #expect(resolved.steps[2].launchMode == .backgroundManagedProcess)
        #expect(resolved.steps[2].workingDirectory == workspaceRoot)
        #expect(resolved.steps[0].shellCommand == "PORT=3000 pnpm dev")
    }

    @Test("Startup profile resolution fails when a step command is empty")
    func startupProfileRequiresCommand() {
        let step = StartupProfileStep(displayName: "Broken", command: "   ")
        let profile = StartupProfile(displayName: "Broken", steps: [step])
        let settings = RepositorySettings(
            startupProfiles: [profile],
            defaultStartupProfileID: profile.id
        )

        #expect(throws: RepositoryLaunchResolutionError.stepCommandMissing(stepName: "Broken")) {
            try RepositoryLaunchPlanner.resolveDefaultStartupProfile(
                in: settings,
                workspaceRoot: URL(fileURLWithPath: "/tmp/devys/repo")
            )
        }
    }
}
