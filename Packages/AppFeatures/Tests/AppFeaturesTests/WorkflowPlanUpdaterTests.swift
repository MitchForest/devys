import AppFeatures
import Testing

@Suite("WorkflowPlanUpdater Tests")
struct WorkflowPlanUpdaterTests {
    @Test("Appends into an existing follow-up section")
    func appendsToExistingSection() throws {
        let content = """
        ## Phase 1
        - [ ] Ship the reducer
        
        ### Follow-Ups
        - [ ] Investigate launch failure
        """

        let updated = try WorkflowPlanUpdater.appendFollowUp(
            content: content,
            request: WorkflowPlanAppendRequest(
                planFilePath: "/tmp/plan.md",
                phaseIndex: 0,
                sectionTitle: "Follow-Ups",
                text: "Capture relaunch diagnostics"
            )
        )

        let snapshot = WorkflowPlanParser.parse(content: updated, planFilePath: "/tmp/plan.md")
        #expect(snapshot.phases.count == 1)
        #expect(snapshot.phases[0].openTickets.map { $0.text } == [
            "Ship the reducer",
            "Investigate launch failure",
            "Capture relaunch diagnostics"
        ])
        #expect(snapshot.phases[0].openTickets[2].section == .followUps)
    }

    @Test("Creates a named section when it is missing")
    func createsMissingNamedSection() throws {
        let content = """
        ## Phase 1
        - [ ] Ship the reducer
        """

        let updated = try WorkflowPlanUpdater.appendFollowUp(
            content: content,
            request: WorkflowPlanAppendRequest(
                planFilePath: "/tmp/plan.md",
                phaseIndex: 0,
                sectionTitle: "Review Notes",
                text: "Add restore coverage for workflow tabs"
            )
        )

        let snapshot = WorkflowPlanParser.parse(content: updated, planFilePath: "/tmp/plan.md")
        #expect(snapshot.phases.count == 1)
        #expect(snapshot.phases[0].openTickets.map { $0.text } == [
            "Ship the reducer",
            "Add restore coverage for workflow tabs"
        ])
        #expect(snapshot.phases[0].openTickets[1].section == .named("Review Notes"))
    }
}
