import Foundation
import FrameworkKit
import PDFKit
import SwiftData
import Testing
@testable import FrameworkApp

@Suite("Exports and backups", .serialized)
@MainActor
struct ExportTests {
    let container: ModelContainer
    let context: ModelContext
    let service: AssessmentService

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        context = container.mainContext
        service = AssessmentService(context: context)
        EvidenceFileStore.rootOverride = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-tests-\(UUID().uuidString)")
    }

    private func sampleAssessment() throws -> Assessment {
        let a = service.createAssessment(name: "Backup Test", organization: "Org", frameworkIDs: ["csf-2.0", "sp800-171r3"],
                                         scopes: [:])
        let ref = RequirementRef(frameworkID: "csf-2.0", requirementID: "GV.OC-01")
        service.setStatus(.implemented, for: ref, in: a)
        service.update(ref, in: a) { $0.owner = "IT"; $0.notes = "Mission statement, reviewed \"yearly\"" }
        service.setStatus(.notApplicable, for: RequirementRef(frameworkID: "csf-2.0", requirementID: "PR.PS-06"), in: a,
                          reason: "No software development")
        service.setParameter("A.03.01.01.ODP.01", frameworkID: "sp800-171r3", value: "90 days", in: a)
        service.addNote(title: "Note", text: "Checked", to: ref, in: a)
        let stored = try EvidenceFileStore.save(Data("evidence-bytes".utf8), fileExtension: "txt",
                                                originalFileName: "scan.txt", assessmentID: a.id)
        service.addFile(stored, to: ref, in: a)
        try context.save()
        return a
    }

    @Test("Backup then restore recreates answers, parameters, evidence, and files")
    func backupRoundTrip() throws {
        let original = try sampleAssessment()
        let payload = BackupService(context: context).payload(for: [original])
        #expect(payload.files.count == 1)
        let data = try BackupCodec.encode(payload, password: "a long passphrase", iterations: 1_000)
        let decoded = try BackupCodec.decode(data, password: "a long passphrase")

        // Restore into a fresh store, as on a new device.
        let other = try Persistence.makeContainer(inMemory: true)
        let summary = try BackupService(context: other.mainContext).restore(decoded)
        #expect(summary.assessmentNames == ["Backup Test"])
        let restored = try #require(try other.mainContext.fetch(FetchDescriptor<Assessment>()).first)
        #expect(restored.id == original.id)
        let ref = RequirementRef(frameworkID: "csf-2.0", requirementID: "GV.OC-01")
        #expect(restored.status(for: ref) == .implemented)
        #expect(restored.response(for: ref)?.owner == "IT")
        #expect(restored.response(for: RequirementRef(frameworkID: "csf-2.0", requirementID: "PR.PS-06"))?.notApplicableReason
                == "No software development")
        #expect(restored.parameterValueMap(frameworkID: "sp800-171r3") == ["A.03.01.01.ODP.01": "90 days"])
        let evidence = try #require(restored.response(for: ref)?.evidence)
        #expect(evidence.count == 2)
        let file = try #require(evidence.first { $0.kind == .file })
        let storedName = try #require(file.storedFileName)
        let url = try #require(EvidenceFileStore.url(forStoredFile: storedName, assessmentID: restored.id))
        #expect(try Data(contentsOf: url) == Data("evidence-bytes".utf8))
    }

    @Test("Restoring into a store that already has the assessment adds a copy instead of overwriting")
    func restoreDoesNotOverwrite() throws {
        let original = try sampleAssessment()
        let payload = BackupService(context: context).payload(for: [original])
        let summary = try BackupService(context: context).restore(payload)
        #expect(summary.assessmentNames == ["Backup Test (Restored)"])
        let all = try context.fetch(FetchDescriptor<Assessment>())
        #expect(all.count == 2)
        #expect(Set(all.map(\.id)).count == 2)
    }

    @Test("The CSV has one row per requirement and escapes notes")
    func csv() async throws {
        let a = try sampleAssessment()
        let store = try #require(FrameworkStore.bundled())
        let csf = try await store.framework("csf-2.0")
        var all = ExportOptions()
        all.requirements = .all
        let builder = ReportBuilder(assessment: a, frameworks: [csf], options: all)
        let rows = builder.csvRows()
        #expect(rows.count == csf.requirements.count)
        #expect(rows.allSatisfy { $0.count == builder.csvHeader.count })
        let gv = try #require(rows.first { $0[1] == "GV.OC-01" })
        #expect(gv[7] == "Implemented")
        #expect(gv[9] == "IT")
        let text = String(decoding: CSV.data(header: builder.csvHeader, rows: rows).dropFirst(3), as: UTF8.self)
        #expect(text.contains("\"Mission statement, reviewed \"\"yearly\"\"\""))
    }

    @Test("Leaving out notes and owners removes them from the spreadsheet, data file, and report")
    func exportOptionsLeaveOutFields() async throws {
        let a = try sampleAssessment()
        let store = try #require(FrameworkStore.bundled())
        let csf = try await store.framework("csf-2.0")
        var options = ExportOptions()
        options.notes = false
        options.ownership = false
        let builder = ReportBuilder(assessment: a, frameworks: [csf], options: options)
        #expect(!builder.csvHeader.contains("Notes"))
        #expect(!builder.csvHeader.contains("Owner"))
        let csvText = String(decoding: builder.csvData(), as: UTF8.self)
        #expect(!csvText.contains("Mission statement"))
        #expect(!csvText.contains("Checked"), "Note evidence text follows the Notes choice")
        #expect(csvText.contains("Note: Note"), "The evidence list still names the note")

        let json = String(decoding: try builder.jsonData(), as: UTF8.self)
        #expect(json.contains("\"GV.OC-01\""))
        #expect(!json.contains("Mission statement"))
        #expect(!json.contains("\"owner\""))

        var pdfOptions = options
        pdfOptions.format = .pdf
        let pdf = try #require(PDFDocument(data: PDFReport(assessment: a, frameworks: [csf], graph: nil, options: pdfOptions).makeData()))
        #expect(pdf.string?.contains("Mission statement") == false)
        #expect(pdf.string?.contains("Owner: IT") == false)

        let full = try #require(PDFDocument(data: PDFReport(assessment: a, frameworks: [csf], graph: nil).makeData()))
        #expect(full.string?.contains("Mission statement") == true)
    }

    @Test("Open items only leaves out implemented and not applicable requirements")
    func openItemsFilter() async throws {
        let a = try sampleAssessment()
        let store = try #require(FrameworkStore.bundled())
        let csf = try await store.framework("csf-2.0")
        var options = ExportOptions()
        options.requirements = .open
        let ids = ReportBuilder(assessment: a, frameworks: [csf], options: options).rows().map(\.requirement.displayId)
        #expect(!ids.contains("GV.OC-01"))
        #expect(!ids.contains("PR.PS-06"))
        #expect(ids.contains("GV.OC-02"))
    }

    @Test("Saved export choices survive a round trip, and unreadable data falls back to defaults")
    func optionsPersistence() {
        var o = ExportOptions()
        o.format = .json
        o.notes = false
        #expect(ExportOptions.decode(o.encoded) == o)
        #expect(ExportOptions.decode(Data("junk".utf8)) == ExportOptions())
    }

    @Test("The PDF report renders several pages with the assessment name")
    func pdf() async throws {
        let a = try sampleAssessment()
        let store = try #require(FrameworkStore.bundled())
        let frameworks = [try await store.framework("csf-2.0"), try await store.framework("sp800-171r3")]
        let data = PDFReport(assessment: a, frameworks: frameworks, graph: try await store.mappingGraph()).makeData()
        #expect(data.prefix(4) == Data("%PDF".utf8))
        let doc = try #require(PDFDocument(data: data))
        #expect(doc.pageCount >= 4)
        #expect(doc.string?.contains("Backup Test") == true)
        #expect(doc.string?.contains("not a certification") == true)
    }

    @Test("Everything is free today, and every premium feature is unlocked")
    func entitlements() {
        let manager = EntitlementManager()
        #expect(EntitlementManager.freeTierUnlocksEverything)
        #expect(PremiumFeature.allCases.allSatisfy(manager.isUnlocked))
    }
}
