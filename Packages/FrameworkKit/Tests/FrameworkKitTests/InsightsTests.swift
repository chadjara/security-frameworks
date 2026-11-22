import Foundation
import Testing
@testable import FrameworkKit

@Suite("Insights")
struct InsightsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ref(_ f: String, _ r: String) -> RequirementRef { RequirementRef(frameworkID: f, requirementID: r) }

    @Test("CSF Tiers are bundled, numbered 1-4, with NIST's titles")
    func tiers() async throws {
        let csf = try await TestContent.store.framework("csf-2.0")
        #expect(csf.document.tiers.map(\.title) == ["Partial", "Risk Informed", "Repeatable", "Adaptive"])
        #expect(csf.document.tiers.allSatisfy { !$0.governance.isEmpty && !$0.management.isEmpty })
        #expect(csf.document.tiersSource?.url.hasPrefix("https://nvlpubs.nist.gov/") == true)
        let sp53 = try await TestContent.store.framework("sp800-53r5")
        #expect(sp53.document.tiers.isEmpty)
    }

    @Test("Next steps: overdue, then in progress, then priority, then foundational")
    func ordering() async throws {
        let csf = try await TestContent.store.framework("csf-2.0")
        let facts: [RequirementRef: ResponseFacts] = [
            ref("csf-2.0", "PR.AA-01"): ResponseFacts(status: .notStarted, priority: .high),
            ref("csf-2.0", "DE.CM-01"): ResponseFacts(status: .inProgress),
            ref("csf-2.0", "RC.RP-01"): ResponseFacts(status: .notStarted, targetDate: now.addingTimeInterval(-86_400)),
            ref("csf-2.0", "GV.OC-01"): ResponseFacts(status: .implemented),
        ]
        let steps = NextStepsEngine.rank(frameworks: [csf], scopes: [:], facts: facts, graph: nil, now: now)
        #expect(steps.prefix(3).map(\.ref.requirementID) == ["RC.RP-01", "DE.CM-01", "PR.AA-01"])
        // Next come unprioritized Govern outcomes (foundational), in document order.
        #expect(steps[3].ref.requirementID == "GV.OC-02")
        #expect(!steps.contains { $0.ref.requirementID == "GV.OC-01" }, "Implemented items are not next steps")
        #expect(steps.first?.reasons.contains(.overdue(now.addingTimeInterval(-86_400))) == true)
        #expect(steps.count == 105)
    }

    @Test("Outcomes excluded from the CSF Target Profile are not next steps")
    func targetProfileExclusion() async throws {
        let csf = try await TestContent.store.framework("csf-2.0")
        let facts = [ref("csf-2.0", "GV.OC-01"): ResponseFacts(inTargetProfile: false)]
        let steps = NextStepsEngine.rank(frameworks: [csf], scopes: [:], facts: facts, graph: nil, now: now)
        #expect(!steps.contains { $0.ref.requirementID == "GV.OC-01" })
    }

    @Test("Next steps respect SP 800-53 scope and count reuse through NIST mappings only")
    func scopeAndReuse() async throws {
        let sp53 = try await TestContent.store.framework("sp800-53r5")
        let sp171 = try await TestContent.store.framework("sp800-171r3")
        let graph = try await TestContent.store.mappingGraph()
        let steps = NextStepsEngine.rank(frameworks: [sp53, sp171], scopes: ["sp800-53r5": ScopeSelection(baselineID: "low")],
                                         facts: [:], graph: graph, now: now)
        #expect(steps.filter { $0.ref.frameworkID == "sp800-53r5" }.count == 149)
        let ac2 = try #require(steps.first { $0.ref == ref("sp800-53r5", "ac-2") })
        let published = graph.links(from: ref("sp800-53r5", "ac-2"), enabledFrameworks: ["sp800-53r5", "sp800-171r3"])
        #expect(ac2.reasons.contains(.coversMapped(Set(published.map(\.target)).count)))
        // Policy controls come before other unprioritized, unstarted items.
        #expect(steps.first?.ref.requirementID.hasSuffix("-1") == true || steps.first?.ref.requirementID == "03.15.01")
    }

    @Test("Profile analysis: targeted, achieved, excluded, and gaps by priority")
    func profile() async throws {
        let csf = try await TestContent.store.framework("csf-2.0")
        let facts: [String: ResponseFacts] = [
            "GV.OC-01": ResponseFacts(status: .implemented),
            "GV.OC-02": ResponseFacts(status: .inProgress, priority: .low),
            "GV.OC-03": ResponseFacts(inTargetProfile: false),
            "GV.OC-04": ResponseFacts(status: .notApplicable),
            "GV.OC-05": ResponseFacts(priority: .high),
        ]
        let summary = ProfileAnalysis.summarize(csf, facts: facts)
        let gv = try #require(summary.first { $0.groupID == "GV" })
        let gvTotal = csf.requirements(inGroup: "GV").count
        #expect(gv.excluded == 2)
        #expect(gv.targeted == gvTotal - 2)
        #expect(gv.achieved == 1)
        #expect(gv.inProgress == 1)
        #expect(gv.gap == gv.targeted - 1)
        #expect(summary.count == 6)

        let gaps = ProfileAnalysis.gaps(csf, facts: facts)
        #expect(gaps.first?.id == "GV.OC-05")
        #expect(!gaps.contains { $0.id == "GV.OC-01" || $0.id == "GV.OC-03" || $0.id == "GV.OC-04" })
    }

    @Test("Progress by family and by baseline")
    func coverage() async throws {
        let sp53 = try await TestContent.store.framework("sp800-53r5")
        let statuses: [String: RequirementStatus] = ["ac-1": .implemented, "ac-2": .implemented, "ac-2.1": .inProgress]
        let byFamily = sp53.progressByTopGroup(scope: ScopeSelection(baselineID: "moderate"), statuses: statuses)
        #expect(byFamily.reduce(0) { $0 + $1.progress.total } == 287)
        let ac = try #require(byFamily.first { $0.group.id == "ac" })
        #expect(ac.progress.implemented == 2)
        #expect(ac.progress.inProgress == 1)
        let byBaseline = sp53.progressByBaseline(statuses: statuses)
        #expect(byBaseline.map(\.baseline.id) == ["low", "moderate", "high", "privacy"])
        #expect(byBaseline.first { $0.baseline.id == "low" }?.progress.implemented == 2)
        #expect(byBaseline.first { $0.baseline.id == "low" }?.progress.total == 149)
    }
}
