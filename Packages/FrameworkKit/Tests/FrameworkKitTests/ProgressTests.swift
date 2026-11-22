import Testing
@testable import FrameworkKit

@Suite("Progress")
struct ProgressTests {
    @Test("Not applicable items are excluded from the denominator")
    func excludesNotApplicable() {
        let p = ProgressSummary(statuses: [.implemented, .implemented, .inProgress, .notStarted, .notApplicable])
        #expect(p.total == 5)
        #expect(p.applicable == 4)
        #expect(p.answered == 4)
        #expect(p.fractionImplemented == 0.5)
        #expect(!p.isComplete)
    }

    @Test("Missing statuses count as not started")
    func missingIsNotStarted() {
        let p = ProgressSummary(ids: ["a", "b", "c"], statuses: ["a": .implemented])
        #expect(p.notStarted == 2)
        #expect(p.implemented == 1)
    }

    @Test("Edge cases: empty, all not applicable, all done")
    func edges() {
        #expect(ProgressSummary().fractionImplemented == 0)
        #expect(!ProgressSummary().isComplete)
        let allNA = ProgressSummary(statuses: [.notApplicable, .notApplicable])
        #expect(allNA.fractionImplemented == 1)
        #expect(allNA.isComplete)
        let done = ProgressSummary(statuses: [.implemented, .notApplicable])
        #expect(done.isComplete)
        #expect(done.fractionImplemented == 1)
    }

    @Test("Summaries add")
    func addition() {
        let p = ProgressSummary(statuses: [.implemented]) + ProgressSummary(statuses: [.notStarted, .inProgress])
        #expect(p.total == 3)
        #expect(p.count(.inProgress) == 1)
    }
}
