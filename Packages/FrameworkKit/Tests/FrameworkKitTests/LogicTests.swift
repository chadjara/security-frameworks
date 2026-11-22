import Foundation
import Testing
@testable import FrameworkKit

@Suite("Decoding")
struct DecodingTests {
    @Test("Optional arrays default to empty")
    func optionalArrays() throws {
        let doc = try TestContent.decode(FrameworkDocument.self, TestContent.miniFrameworkJSON)
        #expect(doc.notices.isEmpty)
        #expect(doc.withdrawn.isEmpty)
        let ac21 = try #require(doc.requirements.first { $0.id == "ac-2.1" })
        #expect(ac21.parameters.isEmpty)
        #expect(ac21.examples.isEmpty)
        #expect(ac21.baselines.isEmpty)
    }

    @Test("A newer schema version is rejected with a clear error")
    func newerSchemaRejected() throws {
        let json = TestContent.miniFrameworkJSON.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2")
        #expect(throws: ContentError.unsupportedSchemaVersion(found: 2, supported: 1)) {
            _ = try TestContent.decode(FrameworkDocument.self, json)
        }
    }

    @Test("Mini framework validates cleanly")
    func miniValidates() throws {
        let doc = try TestContent.decode(FrameworkDocument.self, TestContent.miniFrameworkJSON)
        #expect(ContentValidator.validate(doc).filter { $0.severity == .error }.isEmpty)
    }

    @Test("Validator reports broken references")
    func validatorCatchesErrors() throws {
        let broken = TestContent.miniFrameworkJSON
            .replacingOccurrences(of: "\"parentId\": \"ac-2\"", with: "\"parentId\": \"ac-9\"")
            .replacingOccurrences(of: "{{param:ac-02_odp}}", with: "{{param:nope}}")
        let doc = try TestContent.decode(FrameworkDocument.self, broken)
        let messages = ContentValidator.validate(doc).map(\.message)
        #expect(messages.contains { $0.contains("unknown parent ac-9") })
        #expect(messages.contains { $0.contains("unknown parameter nope") })
    }
}

@Suite("Parameter text")
struct ParameterTextTests {
    let doc: FrameworkDocument
    let framework: Framework

    init() throws {
        doc = try TestContent.decode(FrameworkDocument.self, TestContent.miniFrameworkJSON)
        framework = Framework(document: doc)
    }

    @Test("Unset parameters render as placeholders")
    func placeholders() throws {
        let r = try #require(framework.requirement("ac-2"))
        let text = try #require(r.statement.first?.text)
        #expect(ParameterText.plain(text, parameters: framework.parameterScope(for: r), values: [:])
                == "Disable accounts after [time period].")
    }

    @Test("Values replace tokens, and enhancements resolve their parent's parameters by alt ID")
    func valuesAndAltIDs() throws {
        let r = try #require(framework.requirement("ac-2.1"))
        let text = try #require(r.statement.first?.text)
        let rendered = ParameterText.plain(text, parameters: framework.parameterScope(for: r), values: ["ac-02_odp": "30 days"])
        #expect(rendered == "Support account management within 30 days.")
    }

    @Test("Aggregate parameters show their parts' values")
    func aggregates() throws {
        let r = try #require(framework.requirement("ac-1"))
        let text = try #require(r.statement.first?.text)
        let scope = framework.parameterScope(for: r)
        #expect(ParameterText.plain(text, parameters: scope, values: [:]) == "Disseminate to [personnel or roles].")
        #expect(ParameterText.plain(text, parameters: scope, values: ["ac-01_odp.01": "CISO", "ac-01_odp.02": "CISO"])
                == "Disseminate to CISO.")
        #expect(r.editableParameters.map(\.id) == ["ac-01_odp.01", "ac-01_odp.02"])
    }

    @Test("Segments split text and parameters; unterminated tokens stay literal")
    func segments() {
        let segs = ParameterText.segments(in: "a {{param:x}} b {{param:y", parameters: [:], values: [:])
        #expect(segs.count == 3)
        #expect(segs[0] == .text("a "))
        #expect(segs[2] == .text(" b {{param:y"))
        #expect(ParameterText.tokens(in: "{{param:p1}} and {{param:p2}}") == ["p1", "p2"])
    }
}

@Suite("Scope")
struct ScopeTests {
    let framework: Framework

    init() throws {
        framework = Framework(document: try TestContent.decode(FrameworkDocument.self, TestContent.miniFrameworkJSON))
    }

    @Test("Full catalog when no baseline is chosen")
    func fullCatalog() {
        #expect(framework.requirementsInScope(.fullCatalog).count == 3)
        #expect(framework.requirementsOutOfScope(.fullCatalog).isEmpty)
    }

    @Test("Baseline, additive baseline, and manual additions")
    func baselines() {
        #expect(framework.requirementsInScope(ScopeSelection(baselineID: "low")).map(\.id) == ["ac-1", "ac-2"])
        #expect(framework.requirementsInScope(ScopeSelection(additiveBaselineIDs: ["privacy"])).map(\.id) == ["ac-1"])
        let added = ScopeSelection(baselineID: "low", addedRequirementIDs: ["ac-2.1"])
        #expect(framework.requirementsInScope(added).map(\.id) == ["ac-1", "ac-2", "ac-2.1"])
        #expect(framework.requirementsOutOfScope(ScopeSelection(baselineID: "low")).map(\.id) == ["ac-2.1"])
    }

    @Test("Bundled SP 800-53: Low plus Privacy is the union of both baselines")
    func bundledUnion() async throws {
        let sp53 = try await TestContent.store.framework("sp800-53r5")
        let low = Set(sp53.requirementsInScope(ScopeSelection(baselineID: "low")).map(\.id))
        let privacy = Set(sp53.requirementsInScope(ScopeSelection(additiveBaselineIDs: ["privacy"])).map(\.id))
        let both = sp53.requirementsInScope(ScopeSelection(baselineID: "low", additiveBaselineIDs: ["privacy"]))
        #expect(Set(both.map(\.id)) == low.union(privacy))
    }

    @Test("Frameworks without baselines are always fully in scope")
    func noBaselines() async throws {
        let csf = try await TestContent.store.framework("csf-2.0")
        #expect(csf.requirementsInScope(ScopeSelection(baselineID: "low")).count == 106)
    }
}

@Suite("Mapping graph")
struct MappingGraphTests {
    @Test("Forward and reverse links come only from mapping files")
    func links() async throws {
        let graph = try await TestContent.store.mappingGraph()
        let r171 = RequirementRef(frameworkID: "sp800-171r3", requirementID: "03.01.01")
        let forward = graph.links(from: r171)
        #expect(forward.contains { $0.target == RequirementRef(frameworkID: "sp800-53r5", requirementID: "ac-2")
                                 && $0.direction == .forward && $0.relationship == .sourceControl })

        let ac2 = RequirementRef(frameworkID: "sp800-53r5", requirementID: "ac-2")
        let reverse = graph.links(from: ac2)
        #expect(reverse.contains { $0.target == r171 && $0.direction == .reverse })
        #expect(reverse.contains { $0.target.frameworkID == "csf-2.0" && $0.relationship == .informativeReference })
    }

    @Test("Links can be limited to enabled frameworks")
    func filtering() async throws {
        let graph = try await TestContent.store.mappingGraph()
        let ac2 = RequirementRef(frameworkID: "sp800-53r5", requirementID: "ac-2")
        let onlyCSF = graph.links(from: ac2, enabledFrameworks: ["csf-2.0"])
        #expect(!onlyCSF.isEmpty)
        #expect(onlyCSF.allSatisfy { $0.target.frameworkID == "csf-2.0" })
        #expect(graph.links(from: ac2, enabledFrameworks: []).isEmpty)
    }

    @Test("No link is invented: pair count equals the sum of mapping entries")
    func noInferredLinks() async throws {
        let graph = try await TestContent.store.mappingGraph()
        let index = try await TestContent.store.index()
        #expect(graph.pairCount == index.mappings.reduce(0) { $0 + $1.pairs })
        let csf = RequirementRef(frameworkID: "csf-2.0", requirementID: "PR.AA-01")
        // CSF links only to what CPRT publishes for it; nothing is chained through SP 800-53.
        let published = graph.documents.filter { $0.fromFramework == "csf-2.0" }
            .flatMap { doc in doc.entries.filter { $0.from == "PR.AA-01" }.flatMap(\.to) }
        #expect(graph.links(from: csf).count == published.count)
    }
}

@Suite("Search")
struct SearchTests {
    @Test("Identifier queries rank the exact requirement first")
    func identifiers() async throws {
        let sp53 = try await TestContent.store.searchIndex(for: "sp800-53r5")
        #expect(sp53.search("AC-2").first?.requirementID == "ac-2")
        #expect(sp53.search("ac-02(01)").first?.requirementID == "ac-2.1")
        #expect(sp53.search("SI-4(5)").first?.requirementID == "si-4.5")

        let csf = try await TestContent.store.searchIndex(for: "csf-2.0")
        #expect(csf.search("GV.OC-01").first?.requirementID == "GV.OC-01")
        #expect(csf.search("gv.oc").count == 5)

        let sp171 = try await TestContent.store.searchIndex(for: "sp800-171r3")
        #expect(sp171.search("03.01.01").first?.requirementID == "03.01.01")
        #expect(sp171.search("3.1.1").first?.requirementID == "03.01.01")
    }

    @Test("Text queries match all words by prefix")
    func text() async throws {
        let sp53 = try await TestContent.store.searchIndex(for: "sp800-53r5")
        let hits = sp53.search("inactivity logout").map(\.requirementID)
        #expect(hits.first == "ac-2.5")
        #expect(sp53.search("account manag").map(\.requirementID).prefix(5).contains("ac-2"))
        #expect(sp53.search("zzzzqqq").isEmpty)
        #expect(sp53.search("   ").isEmpty)
    }

    @Test("Tokenizer and identifier segmentation")
    func tokenizing() {
        #expect(SearchIndex.tokenize("Multi-factor Authentication, the Résumé") == ["multi", "factor", "authentication", "resume"])
        #expect(SearchIndex.identifierSegments("AC-02(01)") == ["ac", "2", "1"])
        #expect(SearchIndex.identifierSegments("GV.OC-01") == ["gv", "oc", "1"])
        #expect(SearchIndex.identifierSegments("03.01.01") == ["3", "1", "1"])
        #expect(SearchIndex.identifierScore(query: ["ac", "2"], id: ["ac", "2"]) == 100)
        #expect(SearchIndex.identifierScore(query: ["ac", "3"], id: ["ac", "2"]) == nil)
    }
}

@Suite("Store")
struct StoreTests {
    @Test("Frameworks are cached after the first load")
    func caching() async throws {
        let store = FrameworkStore(contentDirectory: TestContent.directory)
        let a = try await store.framework("csf-2.0")
        let b = try await store.framework("csf-2.0")
        #expect(a.document == b.document)
    }

    @Test("Unknown framework and missing directory produce clear errors")
    func errors() async throws {
        let store = FrameworkStore(contentDirectory: TestContent.directory)
        await #expect(throws: ContentError.unknownFramework("nope")) { _ = try await store.framework("nope") }
        let missing = FrameworkStore(contentDirectory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        await #expect(throws: ContentError.self) { _ = try await missing.index() }
    }

    @Test("A framework file not listed in index.json is discovered automatically")
    func discovery() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fk-\(UUID().uuidString)")
        let frameworks = tmp.appendingPathComponent("frameworks")
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.copyItem(at: TestContent.directory.appendingPathComponent("index.json"),
                                         to: tmp.appendingPathComponent("index.json"))
        try Data(TestContent.miniFrameworkJSON.utf8).write(to: frameworks.appendingPathComponent("mini.framework.json"))

        let store = FrameworkStore(contentDirectory: tmp)
        let index = try await store.index()
        let entry = try #require(index.frameworks.first { $0.id == "mini" })
        #expect(entry.counts.requirements == 3)
        #expect(entry.counts.byBaseline?["low"]?["control"] == 2)
        let fw = try await store.framework("mini")
        #expect(fw.requirements.count == 3)
    }
}
