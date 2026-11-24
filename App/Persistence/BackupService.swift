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
        return try ExportFiles.write(data, named: "\(name) Backup \(stamp).fwbackup")
    }

    // MARK: Restore

    struct RestoreSummary: Equatable {
        let assessmentNames: [String]
    }

    func decode(_ data: Data, password: String) async throws -> BackupPayload {
        try await Task.detached(priority: .userInitiated) {
            try BackupCodec.decode(data, password: password)
        }.value
    }

    /// Imports every assessment in the payload as a new assessment. Nothing existing is overwritten:
    /// an assessment whose ID already exists is given a new ID and "(Restored)" is added to its name.
    @discardableResult
    func restore(_ payload: BackupPayload) throws -> RestoreSummary {
        let existing = Set((try? context.fetch(FetchDescriptor<Assessment>()))?.map(\.id) ?? [])
        var names: [String] = []
        for record in payload.archive.assessments {
            let collides = existing.contains(record.id)
            let a = Assessment(name: collides ? "\(record.name) (Restored)" : record.name,
                               organization: record.organization, enabledFrameworkIDs: record.enabledFrameworkIDs)
            a.id = collides ? UUID() : record.id
            a.notes = record.notes
            a.createdAt = record.createdAt
            a.updatedAt = record.updatedAt
            a.scopes = record.scopes
            a.csfCurrentTier = record.csfCurrentTier
            a.csfTargetTier = record.csfTargetTier
            context.insert(a)

            var evidenceByID: [UUID: EvidenceItem] = [:]
            for e in record.evidence {
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
                evidenceByID[e.id] = item
            }
            for r in record.responses {
                let response = RequirementResponse(frameworkID: r.frameworkID, requirementID: r.requirementID)
                response.status = r.status
                response.notApplicableReason = r.notApplicableReason
                response.owner = r.owner
                response.targetDate = r.targetDate
                response.notes = r.notes
                response.targetStatusRaw = r.targetStatusRaw
                response.priorityRaw = r.priorityRaw
                response.appliedFromFrameworkID = r.appliedFromFrameworkID
                response.appliedFromRequirementID = r.appliedFromRequirementID
                response.createdAt = r.createdAt
                response.updatedAt = r.updatedAt
                context.insert(response)
                response.assessment = a
                response.evidence = r.evidenceIDs.compactMap { evidenceByID[$0] }
            }
            for p in record.parameterValues {
                let value = ParameterValue(frameworkID: p.frameworkID, parameterID: p.parameterID, value: p.value)
                value.updatedAt = p.updatedAt
                context.insert(value)
                value.assessment = a
            }
            names.append(a.name)
        }
        try context.save()
        return RestoreSummary(assessmentNames: names)
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
