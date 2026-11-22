import Foundation
import Testing
@testable import FrameworkKit

/// Checks against the real, bundled NIST content.
@Suite("Bundled content")
struct BundledContentTests {
    @Test("Index lists the three launch frameworks and three mappings")
    func index() async throws {
        let index = try await TestContent.store.index()
        #expect(index.frameworks.map(\.id) == ["csf-2.0", "sp800-53r5", "sp800-171r3"])
        #expect(Set(index.mappings.map(\.id)) == [
            "sp800-171r3_to_sp800-53r5", "csf-2.0_to_sp800-53r5", "csf-2.0_to_sp800-171r3",
        ])
    }

    @Test("Requirement counts match NIST's published figures")
    func counts() async throws {
        let csf = try await TestContent.store.framework("csf-2.0")
        #expect(csf.requirements.count == 106)
        #expect(csf.groups.count == 6)
        #expect(csf.leafGroups.count == 22)

        let sp171 = try await TestContent.store.framework("sp800-171r3")
        #expect(sp171.requirements.count == 97)
        #expect(sp171.groups.count == 17)

        let sp53 = try await TestContent.store.framework("sp800-53r5")
        #expect(sp53.groups.count == 20)
        #expect(sp53.requirementsInScope(ScopeSelection(baselineID: "low")).count == 149)
        #expect(sp53.requirementsInScope(ScopeSelection(baselineID: "moderate")).count == 287)
        #expect(sp53.requirementsInScope(ScopeSelection(baselineID: "high")).count == 370)
        #expect(sp53.requirementsInScope(ScopeSelection(additiveBaselineIDs: ["privacy"])).count == 96)
    }

    @Test("Index counts agree with the framework files")
    func indexMatchesDocuments() async throws {
        let index = try await TestContent.store.index()
        for entry in index.frameworks {
            let fw = try await TestContent.store.framework(entry.id)
            #expect(entry.counts == FrameworkCounts(document: fw.document), "\(entry.id)")
            #expect(entry.shortName == fw.document.shortName)
        }
    }

    @Test("All bundled content passes validation with no errors")
    func validation() async throws {
        let issues = try await TestContent.store.validateAll()
        let errors = issues.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.prefix(10))")
    }

    @Test("Every mapping endpoint exists in its framework")
    func mappingEndpoints() async throws {
        let graph = try await TestContent.store.mappingGraph()
        for doc in graph.documents {
            let from = try await TestContent.store.framework(doc.fromFramework)
            let to = try await TestContent.store.framework(doc.toFramework)
            for e in doc.entries {
                #expect(from.requirement(e.from) != nil, "\(doc.id): \(e.from)")
                for t in e.to { #expect(to.requirement(t) != nil, "\(doc.id): \(e.from) -> \(t)") }
            }
        }
    }

    @Test("Every requirement has provenance on csrc.nist.gov and its framework records its source")
    func provenance() async throws {
        for id in ["csf-2.0", "sp800-53r5", "sp800-171r3"] {
            let fw = try await TestContent.store.framework(id)
            #expect(fw.document.source.sha256.count == 64)
            #expect(fw.document.source.oscalUrl.hasPrefix("https://raw.githubusercontent.com/usnistgov/oscal-content/"))
            #expect(fw.requirements.allSatisfy { $0.sourceUrl.hasPrefix("https://csrc.nist.gov/") })
        }
    }

    @Test("Known requirements decode with the expected structure")
    func spotChecks() async throws {
        let sp53 = try await TestContent.store.framework("sp800-53r5")
        let ac2 = try #require(sp53.requirement("ac-2"))
        #expect(ac2.displayId == "AC-2")
        #expect(ac2.title == "Account Management")
        #expect(ac2.baselines == ["low", "moderate", "high"])
        #expect(sp53.children(of: "ac-2").first?.id == "ac-2.1")
        #expect(sp53.withdrawnRequirement("ac-2.10") != nil)

        let sp171 = try await TestContent.store.framework("sp800-171r3")
        let r = try #require(sp171.requirement("03.01.01"))
        #expect(r.title == "Account Management")
        #expect(r.editableParameters.count >= 1)
        #expect(sp171.document.notices.contains { $0.id == "cmmc-revision" })

        let csf = try await TestContent.store.framework("csf-2.0")
        let gv = try #require(csf.requirement("GV.OC-01"))
        #expect(gv.examples.isEmpty == false)
        #expect(csf.ancestors(ofGroup: "GV.OC").map(\.id) == ["GV"])
    }

    @Test("Every parameter token in bundled statements resolves")
    func parameterTokensResolve() async throws {
        for id in ["sp800-53r5", "sp800-171r3"] {
            let fw = try await TestContent.store.framework(id)
            for r in fw.requirements {
                let scope = fw.parameterScope(for: r)
                for item in r.statement.flatMap(\.flattened) {
                    for token in ParameterText.tokens(in: item.text ?? "") {
                        #expect(scope[token] != nil, "\(r.id): \(token)")
                    }
                }
            }
        }
    }
}
