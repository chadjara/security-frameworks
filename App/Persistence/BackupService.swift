import Foundation
import FrameworkKit
import SwiftData

/// Creates and restores encrypted backups of assessments, including evidence files.
@MainActor
struct BackupService {
    let context: ModelContext

    enum RestoreError: LocalizedError {
        case missingFile(String)

        var errorDescription: String? {
            switch self {
            case .missingFile(let name): return "The backup is missing the evidence file \(name)."
            }
        }
    }

    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }

    // MARK: Backup

    func payload(for assessments: [Assessment]) -> BackupPayload {
        var files: [String: Data] = [:]
        let records = assessments.map { a -> AssessmentRecord in
            for e in a.evidence {
                if let name = e.storedFileName,
                   let url = EvidenceFileStore.url(forStoredFile: name, assessmentID: a.id),
                   let data = try? Data(contentsOf: url) {
                    files[BackupPayload.fileKey(assessmentID: a.id, storedFileName: name)] = data
                }
            }
            return AssessmentRecord(
                id: a.id, name: a.name, organization: a.organization, notes: a.notes,
                createdAt: a.createdAt, updatedAt: a.updatedAt, enabledFrameworkIDs: a.enabledFrameworkIDs,
                scopes: a.scopes, csfCurrentTier: a.csfCurrentTier, csfTargetTier: a.csfTargetTier,
                responses: a.responses.map { r in
                    ResponseRecord(frameworkID: r.frameworkID, requirementID: r.requirementID, status: r.status,
                                   notApplicableReason: r.notApplicableReason, owner: r.owner, targetDate: r.targetDate,
                                   notes: r.notes, targetStatusRaw: r.targetStatusRaw, priorityRaw: r.priorityRaw,
                                   appliedFromFrameworkID: r.appliedFromFrameworkID,
                                   appliedFromRequirementID: r.appliedFromRequirementID,
                                   createdAt: r.createdAt, updatedAt: r.updatedAt,
                                   evidenceIDs: r.evidence.map(\.id))
                },
                parameterValues: a.parameterValues.map {
                    ParameterValueRecord(frameworkID: $0.frameworkID, parameterID: $0.parameterID, value: $0.value,
                                         updatedAt: $0.updatedAt)
                },
                evidence: a.evidence.map { e in
                    EvidenceRecord(id: e.id, kind: e.kindRaw, title: e.title, text: e.text, urlString: e.urlString,
                                   storedFileName: e.storedFileName, originalFileName: e.originalFileName,
                                   contentTypeIdentifier: e.contentTypeIdentifier, byteCount: e.byteCount,
                                   createdAt: e.createdAt)
                }
            )
        }
        return BackupPayload(archive: BackupArchive(appVersion: Self.appVersion, assessments: records), files: files)
    }

    /// Encrypts on a background thread; PBKDF2 with 600,000 iterations takes a moment.
    func makeBackup(of assessments: [Assessment], password: String) async throws -> URL {
        let payload = payload(for: assessments)
        let data = try await Task.detached(priority: .userInitiated) {
            try BackupCodec.encode(payload, password: password)
        }.value
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let name = assessments.count == 1 ? Self.safeFileName(assessments[0].name) : "Assessments"
        return try ExportFiles.write(data, named: "\(name) \(stamp).fwbackup")
    }

    // MARK: Import

    struct RestoreSummary: Equatable {
        let assessmentNames: [String]
    }

    /// What to do with an assessment in the file that is already on this device (same assessment ID,
    /// for example one a teammate sent back after working on it).
    enum ImportMode: String, CaseIterable, Identifiable, Sendable {
        case merge, replace, keepBoth

        var id: String { rawValue }

        var title: String {
            switch self {
            case .merge: return "Merge updates"
            case .replace: return "Replace"
            case .keepBoth: return "Keep both"
            }
        }

        var detail: String {
            switch self {
            case .merge: return "For each requirement, keep whichever answer was changed most recently. Evidence from both is kept."
            case .replace: return "Remove the copy on this device and use the one in the file."
            case .keepBoth: return "Add the file's version as a separate assessment."
            }
        }
    }

    struct MergeStats: Equatable, Sendable {
        var answersAdded = 0
        var answersUpdated = 0
        var answersKeptNewer = 0
        var evidenceAdded = 0
        var valuesUpdated = 0

        var changed: Bool { answersAdded + answersUpdated + evidenceAdded + valuesUpdated > 0 }
    }

    enum ImportOutcome: Equatable, Sendable {
        case added, addedCopy, replaced, merged(MergeStats)
    }

    struct ImportResult: Equatable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let outcome: ImportOutcome
    }

    func decode(_ data: Data, password: String) async throws -> BackupPayload {
        try await Task.detached(priority: .userInitiated) {
            try BackupCodec.decode(data, password: password)
        }.value
    }

    /// IDs of assessments in the file that already exist on this device.
    func existingIDs(in payload: BackupPayload) -> Set<UUID> {
        let local = Set((try? context.fetch(FetchDescriptor<Assessment>()))?.map(\.id) ?? [])
        return Set(payload.archive.assessments.map(\.id)).intersection(local)
    }

    /// Imports every assessment in the file. New assessments are added as they are; for one that is
    /// already on this device, `modes` decides (merge by default).
    @discardableResult
    func importAssessments(_ payload: BackupPayload, modes: [UUID: ImportMode] = [:]) throws -> [ImportResult] {
        let all = (try? context.fetch(FetchDescriptor<Assessment>())) ?? []
        var results: [ImportResult] = []
        for record in payload.archive.assessments {
            guard let existing = all.first(where: { $0.id == record.id }) else {
                let a = try insertNew(record, id: record.id, name: record.name, payload: payload)
                results.append(ImportResult(id: a.id, name: a.name, outcome: .added))
                continue
            }
            switch modes[record.id] ?? .merge {
            case .merge:
                let stats = try merge(record, into: existing, payload: payload)
                results.append(ImportResult(id: existing.id, name: existing.name, outcome: .merged(stats)))
            case .replace:
                AssessmentService(context: context).delete(existing)
                try context.save()
                let a = try insertNew(record, id: record.id, name: record.name, payload: payload)
                results.append(ImportResult(id: a.id, name: a.name, outcome: .replaced))
            case .keepBoth:
                let a = try insertNew(record, id: UUID(), name: "\(record.name) (Imported)", payload: payload)
                results.append(ImportResult(id: a.id, name: a.name, outcome: .addedCopy))
            }
        }
        try context.save()
        return results
    }

    /// Imports every assessment as a new assessment, never touching existing ones.
    @discardableResult
    func restore(_ payload: BackupPayload) throws -> RestoreSummary {
        let modes = Dictionary(uniqueKeysWithValues: payload.archive.assessments.map { ($0.id, ImportMode.keepBoth) })
        return RestoreSummary(assessmentNames: try importAssessments(payload, modes: modes).map(\.name))
    }

    // MARK: Import helpers

    private func insertNew(_ record: AssessmentRecord, id: UUID, name: String, payload: BackupPayload) throws -> Assessment {
        let a = Assessment(name: name, organization: record.organization, enabledFrameworkIDs: record.enabledFrameworkIDs)
        a.id = id
        a.notes = record.notes
        a.createdAt = record.createdAt
        a.updatedAt = record.updatedAt
        a.scopes = record.scopes
        a.csfCurrentTier = record.csfCurrentTier
        a.csfTargetTier = record.csfTargetTier
        context.insert(a)

        var evidenceByID: [UUID: EvidenceItem] = [:]
        for e in record.evidence {
            evidenceByID[e.id] = try makeEvidence(e, from: record, payload: payload, into: a)
        }
        for r in record.responses {
            let response = RequirementResponse(frameworkID: r.frameworkID, requirementID: r.requirementID)
            apply(r, to: response)
            response.createdAt = r.createdAt
            context.insert(response)
            response.assessment = a
            response.evidence = r.evidenceIDs.compactMap { evidenceByID[$0] }
        }
        for p in record.parameterValues {
            insertValue(p, into: a)
        }
        return a
    }

    /// Newest edit wins, item by item. Evidence is combined. Nothing on this device that is newer than
    /// the file is changed, so importing the same file twice changes nothing the second time.
    private func merge(_ record: AssessmentRecord, into a: Assessment, payload: BackupPayload) throws -> MergeStats {
        var stats = MergeStats()
        if record.updatedAt > a.updatedAt {
            a.name = record.name
            a.organization = record.organization
            a.notes = record.notes
            a.scopes = record.scopes
            a.csfCurrentTier = record.csfCurrentTier
            a.csfTargetTier = record.csfTargetTier
        }
        // Turning a framework on is additive; turning one off never removes answers anyway.
        let missing = record.enabledFrameworkIDs.filter { !a.enabledFrameworkIDs.contains($0) }
        if !missing.isEmpty { a.enabledFrameworkIDs += missing }

        var evidenceByID = Dictionary(a.evidence.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for e in record.evidence where evidenceByID[e.id] == nil {
            evidenceByID[e.id] = try makeEvidence(e, from: record, payload: payload, into: a)
            stats.evidenceAdded += 1
        }

        var responses = Dictionary(a.responses.map { ("\($0.frameworkID)|\($0.requirementID)", $0) },
                                   uniquingKeysWith: { first, _ in first })
        for r in record.responses {
            let key = "\(r.frameworkID)|\(r.requirementID)"
            let linked = r.evidenceIDs.compactMap { evidenceByID[$0] }
            if let local = responses[key] {
                if r.updatedAt > local.updatedAt {
                    apply(r, to: local)
                    stats.answersUpdated += 1
                } else if r.updatedAt < local.updatedAt {
                    stats.answersKeptNewer += 1
                }
                let have = Set(local.evidence.map(\.id))
                let added = linked.filter { !have.contains($0.id) }
                if !added.isEmpty { local.evidence += added }
            } else {
                let response = RequirementResponse(frameworkID: r.frameworkID, requirementID: r.requirementID)
                apply(r, to: response)
                response.createdAt = r.createdAt
                context.insert(response)
                response.assessment = a
                response.evidence = linked
                responses[key] = response
                stats.answersAdded += 1
            }
        }

        for p in record.parameterValues {
            if let local = a.parameterValues.first(where: { $0.frameworkID == p.frameworkID && $0.parameterID == p.parameterID }) {
                if p.updatedAt > local.updatedAt {
                    local.value = p.value
                    local.updatedAt = p.updatedAt
                    stats.valuesUpdated += 1
                }
            } else {
                insertValue(p, into: a)
                stats.valuesUpdated += 1
            }
        }
        a.updatedAt = max(a.updatedAt, record.updatedAt)
        return stats
    }

    private func apply(_ r: ResponseRecord, to response: RequirementResponse) {
        response.status = r.status
        response.notApplicableReason = r.notApplicableReason
        response.owner = r.owner
        response.targetDate = r.targetDate
        response.notes = r.notes
        response.targetStatusRaw = r.targetStatusRaw
        response.priorityRaw = r.priorityRaw
        response.appliedFromFrameworkID = r.appliedFromFrameworkID
        response.appliedFromRequirementID = r.appliedFromRequirementID
        response.updatedAt = r.updatedAt
    }

    private func insertValue(_ p: ParameterValueRecord, into a: Assessment) {
        let value = ParameterValue(frameworkID: p.frameworkID, parameterID: p.parameterID, value: p.value)
        value.updatedAt = p.updatedAt
        context.insert(value)
        value.assessment = a
    }

    private func makeEvidence(_ e: EvidenceRecord, from record: AssessmentRecord, payload: BackupPayload,
                              into a: Assessment) throws -> EvidenceItem {
        let item = EvidenceItem(kind: EvidenceKind(rawValue: e.kind) ?? .note, title: e.title)
        item.id = e.id
        item.text = e.text
        item.urlString = e.urlString
        item.originalFileName = e.originalFileName
        item.contentTypeIdentifier = e.contentTypeIdentifier
        item.byteCount = e.byteCount
        item.createdAt = e.createdAt
        if let name = e.storedFileName {
            let key = BackupPayload.fileKey(assessmentID: record.id, storedFileName: name)
            guard let data = payload.files[key] else { throw RestoreError.missingFile(e.originalFileName ?? name) }
            let ext = (name as NSString).pathExtension
            let stored = try EvidenceFileStore.save(data, fileExtension: ext.isEmpty ? "bin" : ext,
                                                    originalFileName: e.originalFileName ?? name, assessmentID: a.id)
            item.storedFileName = stored.storedFileName
        }
        context.insert(item)
        item.assessment = a
        return item
    }

    static func safeFileName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Assessment" : String(cleaned.prefix(60))
    }
}

/// Temporary export files. They live in a protected folder inside the app and are removed on launch.
enum ExportFiles {
    static func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
        }
        return dir
    }

    static func write(_ data: Data, named name: String) throws -> URL {
        let url = try directory().appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Exported copies are meant to be handed off immediately; nothing is kept around.
    static func purge() {
        if let dir = try? directory() { try? FileManager.default.removeItem(at: dir) }
    }
}
