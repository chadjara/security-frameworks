import Foundation
import FrameworkKit
import SwiftData
import Testing
@testable import FrameworkApp

@Suite("Assessment data", .serialized)
@MainActor
struct PersistenceTests {
    let container: ModelContainer
    let context: ModelContext
    let service: AssessmentService

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        context = container.mainContext
        service = AssessmentService(context: context)
        EvidenceFileStore.rootOverride = FileManager.default.temporaryDirectory
            .appendingPathComponent("evidence-tests-\(UUID().uuidString)")
    }

    private func makeAssessment() -> Assessment {
        service.createAssessment(name: "  Test  ", organization: "Org", frameworkIDs: ["csf-2.0", "sp800-171r3"],
                                 scopes: ["sp800-53r5": ScopeSelection(baselineID: "moderate")])
    }

    private let ref = RequirementRef(frameworkID: "csf-2.0", requirementID: "GV.OC-01")

    @Test("Creating an assessment trims names and stores scopes")
    func create() throws {
        let a = makeAssessment()
        #expect(a.name == "Test")
        #expect(a.scope(for: "sp800-53r5").baselineID == "moderate")
        #expect(a.scope(for: "csf-2.0") == .fullCatalog)
        #expect(try context.fetch(FetchDescriptor<Assessment>()).count == 1)
    }

    @Test("Turning a framework off keeps its answers")
    func disableKeepsAnswers() {
        let a = makeAssessment()
        service.setStatus(.implemented, for: ref, in: a)
        a.setEnabled("csf-2.0", false, order: ["csf-2.0", "sp800-53r5", "sp800-171r3"])
        #expect(!a.isEnabled("csf-2.0"))
        #expect(a.status(for: ref) == .implemented)
        a.setEnabled("csf-2.0", true, order: ["csf-2.0", "sp800-53r5", "sp800-171r3"])
        #expect(a.enabledFrameworkIDs == ["csf-2.0", "sp800-171r3"])
        #expect(a.status(for: ref) == .implemented)
    }

    @Test("Not applicable requires a reason")
    func notApplicableNeedsReason() {
        let a = makeAssessment()
        #expect(service.setStatus(.notApplicable, for: ref, in: a) == false)
        #expect(a.status(for: ref) == .notStarted)
        #expect(service.setStatus(.notApplicable, for: ref, in: a, reason: "   ") == false)
        #expect(service.setStatus(.notApplicable, for: ref, in: a, reason: " No wireless networks ") == true)
        #expect(a.status(for: ref) == .notApplicable)
        #expect(a.response(for: ref)?.notApplicableReason == "No wireless networks")
    }

    @Test("One response per requirement")
    func singleResponse() {
        let a = makeAssessment()
        service.setStatus(.inProgress, for: ref, in: a)
        service.update(ref, in: a) { $0.owner = "IT" }
        service.setStatus(.implemented, for: ref, in: a)
        #expect(a.responses.filter { $0.ref == ref }.count == 1)
        #expect(a.statusMap(frameworkID: "csf-2.0") == ["GV.OC-01": .implemented])
    }

    @Test("Parameter values are set, updated, and cleared")
    func parameters() {
        let a = makeAssessment()
        service.setParameter("A.03.01.01.ODP.01", frameworkID: "sp800-171r3", value: "90 days", in: a)
        service.setParameter("A.03.01.01.ODP.01", frameworkID: "sp800-171r3", value: "60 days", in: a)
        #expect(a.parameterValueMap(frameworkID: "sp800-171r3") == ["A.03.01.01.ODP.01": "60 days"])
        service.setParameter("A.03.01.01.ODP.01", frameworkID: "sp800-171r3", value: "", in: a)
        #expect(a.parameterValueMap(frameworkID: "sp800-171r3").isEmpty)
    }

    @Test("Evidence files are stored, and removed with their evidence item")
    func evidenceFiles() throws {
        let a = makeAssessment()
        let stored = try EvidenceFileStore.save(Data("scan".utf8), fileExtension: "txt", originalFileName: "scan.txt",
                                                assessmentID: a.id)
        let item = service.addFile(stored, to: ref, in: a)
        let url = try #require(EvidenceFileStore.url(forStoredFile: stored.storedFileName, assessmentID: a.id))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(a.response(for: ref)?.evidence.count == 1)
        service.remove(item, from: ref, in: a)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(a.response(for: ref)?.evidence.isEmpty == true)
    }

    @Test("Duplicating copies answers, parameters, and evidence files")
    func duplicate() throws {
        let a = makeAssessment()
        service.setStatus(.implemented, for: ref, in: a)
        service.setParameter("p1", frameworkID: "sp800-171r3", value: "v", in: a)
        let stored = try EvidenceFileStore.save(Data("x".utf8), fileExtension: "txt", originalFileName: "x.txt", assessmentID: a.id)
        service.addFile(stored, to: ref, in: a)

        let copy = service.duplicate(a, name: "Copy")
        #expect(copy.id != a.id)
        #expect(copy.status(for: ref) == .implemented)
        #expect(copy.parameterValueMap(frameworkID: "sp800-171r3") == ["p1": "v"])
        #expect(copy.response(for: ref)?.evidence.count == 1)
        let copiedURL = try #require(EvidenceFileStore.url(forStoredFile: stored.storedFileName, assessmentID: copy.id))
        #expect(FileManager.default.fileExists(atPath: copiedURL.path))
    }

    @Test("Deleting an assessment removes its answers, evidence, and files")
    func deleteCascades() throws {
        let a = makeAssessment()
        service.setStatus(.implemented, for: ref, in: a)
        service.addNote(title: "N", text: "T", to: ref, in: a)
        let stored = try EvidenceFileStore.save(Data("x".utf8), fileExtension: "txt", originalFileName: "x.txt", assessmentID: a.id)
        service.addFile(stored, to: ref, in: a)
        let dir = try EvidenceFileStore.directory(for: a.id)
        service.delete(a)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Assessment>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RequirementResponse>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<EvidenceItem>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }
}
