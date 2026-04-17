import AppFeatures
import Testing

@Suite("WorkflowPlanParser Tests")
struct WorkflowPlanParserTests {
    @Test("Parses phase body and named follow-up sections")
    func parsesSections() {
        let content = """
        ## Phase 1
        - [ ] Ship the reducer
        
        ### Follow-Ups
        - [ ] Capture relaunch diagnostics
        
        ### Review Notes
        - [ ] Confirm terminal restore
        
        ## Phase 2
        - [ ] Polish the run tab
        """

        let snapshot = WorkflowPlanParser.parse(
            content: content,
            planFilePath: "/tmp/plan.md"
        )

        #expect(snapshot.phases.count == 2)
        #expect(snapshot.phases[0].openTickets.count == 3)
        #expect(snapshot.phases[0].openTickets[0].section == .phaseBody)
        #expect(snapshot.phases[0].openTickets[1].section == .followUps)
        #expect(snapshot.phases[0].openTickets[2].section == .named("Review Notes"))
        #expect(snapshot.phases[1].openTickets.count == 1)
    }
}
