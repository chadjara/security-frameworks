import Foundation
import FrameworkKit
import SwiftData
import UniformTypeIdentifiers

/// All mutations of assessment data go through here so that timestamps, evidence files, and
/// relationships stay consistent.
@MainActor
struct AssessmentService {
    let context: ModelContext

    // MARK: Assessments

    @discardableResult
    func createAssessment(name: String, organization: String, frameworkIDs: [String],
                          scopes: [String: ScopeSelection]) -> Assessment {
        let a = Assessment(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                           organization: organization.trimmingCharacters(in: .whitespacesAndNewlines),
                           enabledFrameworkIDs: frameworkIDs)
        a.scopes = scopes
        context.insert(a)
        return a
    }

    func delete(_ assessment: Assessment) {
        let id = assessment.id
        context.delete(assessment)
        EvidenceFileStore.deleteAll(for: id)
    }

    /// Copies an assessment with all answers, parameter values, and evidence (including files).
    @discardableResult
    func duplicate(_ source: Assessment, name: String) -> Assessment {
        let copy = Assessment(name: name, organization: source.organization, enabledFrameworkIDs: source.enabledFrameworkIDs)
        copy.notes = source.notes
        copy.scopeData = source.scopeData
        copy.csfCurrentTier = source.csfCurrentTier
        copy.csfTargetTier = source.csfTargetTier
        context.insert(copy)

        var evidenceMap: [UUID: EvidenceItem] = [:]
        for item in source.evidence {
            let e = EvidenceItem(kind: item.kind, title: item.title)
            e.text = item.text
            e.urlString = item.urlString
            e.storedFileName = item.storedFileName
            e.originalFileName = item.originalFileName
            e.contentTypeIdentifier = item.contentTypeIdentifier
            e.byteCount = item.byteCount
            e.createdAt = item.createdAt
            if let name = item.storedFileName {
                try? EvidenceFileStore.copyFile(named: name, from: source.id, to: copy.id)
            }
            context.insert(e)
            e.assessment = copy
            evidenceMap[item.id] = e
        }
        for r in source.responses {
            let n = RequirementResponse(frameworkID: r.frameworkID, requirementID: r.requirementID)
            n.statusRaw = r.statusRaw
            n.notApplicableReason = r.notApplicableReason
            n.owner = r.owner
            n.targetDate = r.targetDate
            n.notes = r.notes
            n.targetStatusRaw = r.targetStatusRaw
            n.priorityRaw = r.priorityRaw
            n.appliedFromFrameworkID = r.appliedFromFrameworkID
            n.appliedFromRequirementID = r.appliedFromRequirementID
            context.insert(n)
            n.assessment = copy
            n.evidence = r.evidence.compactMap { evidenceMap[$0.id] }
        }
        for p in source.parameterValues {
            let n = ParameterValue(frameworkID: p.frameworkID, parameterID: p.parameterID, value: p.value)
            context.insert(n)
            n.assessment = copy
        }
        return copy
    }

    // MARK: Responses

    /// The response for a requirement, created on first use.
    func ensureResponse(_ assessment: Assessment, _ ref: RequirementRef) -> RequirementResponse {
        if let existing = assessment.response(for: ref) { return existing }
        let r = RequirementResponse(frameworkID: ref.frameworkID, requirementID: ref.requirementID)
        context.insert(r)
        r.assessment = assessment
        return r
    }

    /// Sets a status. Not applicable requires a non-empty reason; returns false if it is missing.
    @discardableResult
    func setStatus(_ status: RequirementStatus, for ref: RequirementRef, in assessment: Assessment,
                   reason: String? = nil) -> Bool {
        let response = ensureResponse(assessment, ref)
        if status == .notApplicable {
            let text = (reason ?? response.notApplicableReason).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            response.notApplicableReason = text
        }
        response.status = status
        response.updatedAt = Date()
        assessment.touch()
        return true
    }

    func update(_ ref: RequirementRef, in assessment: Assessment, _ change: (RequirementResponse) -> Void) {
        let response = ensureResponse(assessment, ref)
        change(response)
        response.updatedAt = Date()
        assessment.touch()
    }

    // MARK: Cross-framework reuse

    struct ApplyOptions: Equatable {
        var status = true
        var ownerAndDate = true
        var notes = true
        var evidence = true
    }

    /// Applies an answer to requirements mapped to it by NIST. The user confirms the targets first,
    /// because mappings are not always one-to-one. Existing owner, date, and notes are not overwritten:
    /// notes are appended with attribution, and evidence is linked (shared), not copied.
    func apply(from source: RequirementRef, sourceLabel: String, to targets: [RequirementRef],
               options: ApplyOptions, in assessment: Assessment) {
        guard let from = assessment.response(for: source) else { return }
        for target in targets where target != source {
            let to = ensureResponse(assessment, target)
            if options.status {
                if from.status == .notApplicable {
                    to.notApplicableReason = from.notApplicableReason
                }
                to.status = from.status
            }
            if options.ownerAndDate {
                if to.owner.isEmpty { to.owner = from.owner }
                if to.targetDate == nil { to.targetDate = from.targetDate }
            }
            let notes = from.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if options.notes, !notes.isEmpty, !to.notes.contains(notes) {
                to.notes = to.notes.isEmpty ? notes : "\(to.notes)\n\nFrom \(sourceLabel): \(notes)"
            }
            if options.evidence {
                for item in from.evidence where !to.evidence.contains(where: { $0.id == item.id }) {
                    to.evidence.append(item)
                }
            }
            to.appliedFromFrameworkID = source.frameworkID
            to.appliedFromRequirementID = source.requirementID
            to.updatedAt = Date()
        }
        assessment.touch()
    }

    // MARK: CSF profile

    func setInTargetProfile(_ included: Bool, for ref: RequirementRef, in assessment: Assessment) {
        update(ref, in: assessment) { $0.inTargetProfile = included }
    }

    func setPriority(_ priority: ProfilePriority?, for ref: RequirementRef, in assessment: Assessment) {
        update(ref, in: assessment) { $0.priority = priority }
    }

    // MARK: Parameters

    func setParameter(_ parameterID: String, frameworkID: String, value: String, in assessment: Assessment) {
        if let existing = assessment.parameterValue(frameworkID: frameworkID, parameterID: parameterID) {
            if value.isEmpty {
                assessment.parameterValues.removeAll { $0.persistentModelID == existing.persistentModelID }
                context.delete(existing)
            } else {
                existing.value = value
                existing.updatedAt = Date()
            }
        } else if !value.isEmpty {
            let p = ParameterValue(frameworkID: frameworkID, parameterID: parameterID, value: value)
            context.insert(p)
            p.assessment = assessment
        }
        assessment.touch()
    }

    // MARK: Evidence

    @discardableResult
    func addNote(title: String, text: String, to ref: RequirementRef, in assessment: Assessment) -> EvidenceItem {
        let e = EvidenceItem(kind: .note, title: title.isEmpty ? "Note" : title)
        e.text = text
        attach(e, to: ref, in: assessment)
        return e
    }

    @discardableResult
    func addLink(title: String, url: URL, to ref: RequirementRef, in assessment: Assessment) -> EvidenceItem {
        let e = EvidenceItem(kind: .link, title: title.isEmpty ? (url.host() ?? url.absoluteString) : title)
        e.urlString = url.absoluteString
        attach(e, to: ref, in: assessment)
        return e
    }

    @discardableResult
    func addFile(_ stored: EvidenceFileStore.StoredFile, title: String? = nil, to ref: RequirementRef,
                 in assessment: Assessment) -> EvidenceItem {
        let e = EvidenceItem(kind: .file, title: title ?? stored.originalFileName)
        e.storedFileName = stored.storedFileName
        e.originalFileName = stored.originalFileName
        e.contentTypeIdentifier = stored.contentType?.identifier
        e.byteCount = stored.byteCount
        attach(e, to: ref, in: assessment)
        return e
    }

    private func attach(_ item: EvidenceItem, to ref: RequirementRef, in assessment: Assessment) {
        context.insert(item)
        item.assessment = assessment
        let response = ensureResponse(assessment, ref)
        response.evidence.append(item)
        response.updatedAt = Date()
        assessment.touch()
    }

    /// Detaches evidence from one requirement. The item (and its file) is deleted once no
    /// requirement uses it.
    func remove(_ item: EvidenceItem, from ref: RequirementRef, in assessment: Assessment) {
        if let response = assessment.response(for: ref) {
            response.evidence.removeAll { $0.id == item.id }
            response.updatedAt = Date()
        }
        if item.responses.allSatisfy({ $0.ref == ref }) || item.responses.isEmpty {
            if let name = item.storedFileName { EvidenceFileStore.delete(storedFileName: name, assessmentID: assessment.id) }
            assessment.evidence.removeAll { $0.id == item.id }
            context.delete(item)
        }
        assessment.touch()
    }
}
