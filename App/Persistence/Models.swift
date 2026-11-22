import Foundation
import FrameworkKit
import SwiftData

/// One self-assessment, for example one per organization or per year.
///
/// User answers are keyed by `(frameworkID, requirementID)` strings, so regenerating framework
/// content never requires migrating user data. Turning a framework off only removes it from
/// `enabledFrameworkIDs`; its responses are kept.
@Model
final class Assessment {
    var id: UUID = UUID()
    var name: String = ""
    var organization: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var enabledFrameworkIDs: [String] = []
    /// JSON-encoded `[frameworkID: ScopeSelection]`.
    var scopeData: Data = Data()
    /// CSF Tiers (1–4), used from Phase 3.
    var csfCurrentTier: Int?
    var csfTargetTier: Int?

    @Relationship(deleteRule: .cascade, inverse: \RequirementResponse.assessment)
    var responses: [RequirementResponse] = []

    @Relationship(deleteRule: .cascade, inverse: \EvidenceItem.assessment)
    var evidence: [EvidenceItem] = []

    @Relationship(deleteRule: .cascade, inverse: \ParameterValue.assessment)
    var parameterValues: [ParameterValue] = []

    init(name: String, organization: String = "", enabledFrameworkIDs: [String] = []) {
        self.id = UUID()
        self.name = name
        self.organization = organization
        self.enabledFrameworkIDs = enabledFrameworkIDs
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: Frameworks and scope

    func isEnabled(_ frameworkID: String) -> Bool { enabledFrameworkIDs.contains(frameworkID) }

    func setEnabled(_ frameworkID: String, _ enabled: Bool, order: [String]) {
        var ids = Set(enabledFrameworkIDs)
        if enabled { ids.insert(frameworkID) } else { ids.remove(frameworkID) }
        enabledFrameworkIDs = order.filter(ids.contains) + ids.subtracting(order).sorted()
        touch()
    }

    var scopes: [String: ScopeSelection] {
        get { (try? JSONDecoder().decode([String: ScopeSelection].self, from: scopeData)) ?? [:] }
        set { scopeData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    func scope(for frameworkID: String) -> ScopeSelection { scopes[frameworkID] ?? .fullCatalog }

    func setScope(_ scope: ScopeSelection, for frameworkID: String) {
        var all = scopes
        all[frameworkID] = scope
        scopes = all
        touch()
    }

    func touch() { updatedAt = Date() }

    // MARK: Responses

    func response(for ref: RequirementRef) -> RequirementResponse? {
        responses.first { $0.frameworkID == ref.frameworkID && $0.requirementID == ref.requirementID }
    }

    /// Status of every answered requirement in a framework.
    func statusMap(frameworkID: String) -> [String: RequirementStatus] {
        var out: [String: RequirementStatus] = [:]
        for r in responses where r.frameworkID == frameworkID { out[r.requirementID] = r.status }
        return out
    }

    func status(for ref: RequirementRef) -> RequirementStatus { response(for: ref)?.status ?? .notStarted }

    // MARK: Parameter values

    /// Organization-defined parameter values for a framework, keyed by parameter ID. They are stored per
    /// assessment rather than per response because SP 800-53 enhancements share parameters with
    /// their base control.
    func parameterValueMap(frameworkID: String) -> [String: String] {
        var out: [String: String] = [:]
        for p in parameterValues where p.frameworkID == frameworkID { out[p.parameterID] = p.value }
        return out
    }

    func parameterValue(frameworkID: String, parameterID: String) -> ParameterValue? {
        parameterValues.first { $0.frameworkID == frameworkID && $0.parameterID == parameterID }
    }
}

@Model
final class RequirementResponse {
    var frameworkID: String = ""
    var requirementID: String = ""
    var statusRaw: String = RequirementStatus.notStarted.rawValue
    var notApplicableReason: String = ""
    var owner: String = ""
    var targetDate: Date?
    var notes: String = ""
    /// CSF Organizational Profile fields, used from Phase 3.
    var targetStatusRaw: String?
    var priorityRaw: String?
    /// Set when the answer was applied from a mapped requirement in another framework.
    var appliedFromFrameworkID: String?
    var appliedFromRequirementID: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var assessment: Assessment?

    /// Evidence can be shared by mapped requirements, so this is many-to-many.
    @Relationship(deleteRule: .nullify, inverse: \EvidenceItem.responses)
    var evidence: [EvidenceItem] = []

    init(frameworkID: String, requirementID: String) {
        self.frameworkID = frameworkID
        self.requirementID = requirementID
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var status: RequirementStatus {
        get { RequirementStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    var ref: RequirementRef { RequirementRef(frameworkID: frameworkID, requirementID: requirementID) }

    var sortedEvidence: [EvidenceItem] { evidence.sorted { $0.createdAt < $1.createdAt } }
}

enum EvidenceKind: String, Codable, CaseIterable {
    case note
    case link
    case file

    var systemImage: String {
        switch self {
        case .note: return "text.alignleft"
        case .link: return "link"
        case .file: return "doc"
        }
    }
}

@Model
final class EvidenceItem {
    var id: UUID = UUID()
    var kindRaw: String = EvidenceKind.note.rawValue
    var title: String = ""
    var text: String = ""
    var urlString: String = ""
    /// File name inside this assessment's evidence folder (see EvidenceFileStore).
    var storedFileName: String?
    var originalFileName: String?
    var contentTypeIdentifier: String?
    var byteCount: Int = 0
    var createdAt: Date = Date()

    var assessment: Assessment?
    var responses: [RequirementResponse] = []

    init(kind: EvidenceKind, title: String) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.title = title
        self.createdAt = Date()
    }

    var kind: EvidenceKind { EvidenceKind(rawValue: kindRaw) ?? .note }
}

@Model
final class ParameterValue {
    var frameworkID: String = ""
    var parameterID: String = ""
    var value: String = ""
    var updatedAt: Date = Date()
    var assessment: Assessment?

    init(frameworkID: String, parameterID: String, value: String) {
        self.frameworkID = frameworkID
        self.parameterID = parameterID
        self.value = value
        self.updatedAt = Date()
    }
}
