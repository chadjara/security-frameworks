import FrameworkKit
import Foundation

/// Rows and files shared by the CSV and JSON exports, honoring the user's export options.
@MainActor
struct ReportBuilder {
    let assessment: Assessment
    let frameworks: [Framework]
    var options = ExportOptions()
    /// Used by the PDF's next steps to rank reuse across mapped requirements.
    var graph: MappingGraph?

    private static let dateFormat = Date.ISO8601FormatStyle().year().month().day()

    // MARK: Row selection

    /// The requirements to export, in framework order, filtered by the options.
    func rows() -> [ExportRow] {
        var out: [ExportRow] = []
        for fw in frameworks {
            let scope = assessment.scope(for: fw.id)
            for r in fw.requirements {
                let response = assessment.response(for: RequirementRef(frameworkID: fw.id, requirementID: r.id))
                let inScope = fw.isInScope(r, selection: scope)
                guard options.shouldInclude(inScope: inScope, status: response?.status ?? .notStarted) else { continue }
                out.append(ExportRow(framework: fw, requirement: r, response: response, inScope: inScope))
            }
        }
        return out
    }

    // MARK: CSV

    private struct Column {
        let title: String
        let value: @MainActor (ExportRow) -> String
    }

    private var hasProfileFramework: Bool { frameworks.contains { !$0.document.tiers.isEmpty } }

    private var columns: [Column] {
        var c: [Column] = [
            Column(title: "Framework") { $0.framework.document.shortName },
            Column(title: "Requirement ID") { $0.requirement.displayId },
            Column(title: "Title") { $0.requirement.title },
            Column(title: "Type") { $0.framework.kind($0.requirement.kind)?.singular ?? $0.requirement.kind },
            Column(title: "Group") { row in row.framework.group(row.requirement.groupId).map { "\($0.displayId) \($0.title)" } ?? "" },
            Column(title: "In scope") { $0.inScope ? "Yes" : "No" },
            Column(title: "Baselines") { row in row.requirement.baselines.compactMap { row.framework.baseline($0)?.title }.joined(separator: "; ") },
            Column(title: "Status") { $0.status.title },
        ]
        if options.notApplicableReasons {
            c.append(Column(title: "Not applicable reason") { $0.status == .notApplicable ? ($0.response?.notApplicableReason ?? "") : "" })
        }
        if options.ownership {
            c.append(Column(title: "Owner") { $0.response?.owner ?? "" })
            c.append(Column(title: "Target date") { $0.response?.targetDate.map { $0.formatted(Self.dateFormat) } ?? "" })
        }
        if options.notes {
            c.append(Column(title: "Notes") { $0.response?.notes ?? "" })
        }
        if options.parameters {
            c.append(Column(title: "Organization-defined values") { row in parameterLines(row).joined(separator: "; ") })
        }
        if options.evidence {
            c.append(Column(title: "Evidence items") { "\($0.response?.evidence.count ?? 0)" })
            c.append(Column(title: "Evidence") { row in evidenceLines(row).joined(separator: "\n") })
        }
        c.append(Column(title: "Applied from") { row in
            guard let id = row.response?.appliedFromRequirementID else { return "" }
            return "\(row.response?.appliedFromFrameworkID ?? "") \(id)"
        })
        if options.profile && hasProfileFramework {
            c.append(Column(title: "CSF target profile") { row in
                row.framework.document.tiers.isEmpty ? "" : ((row.response?.inTargetProfile ?? true) ? "Included" : "Excluded")
            })
            c.append(Column(title: "CSF priority") { $0.response?.priority?.title ?? "" })
        }
        c.append(Column(title: "Last updated") { $0.response.map { $0.updatedAt.formatted(Self.dateFormat) } ?? "" })
        if options.nistText {
            c.append(Column(title: "Requirement text") { row in
                StatementText.plain(row.requirement, in: row.framework,
                                    values: options.parameters ? assessment.parameterValueMap(frameworkID: row.framework.id) : [:])
            })
        }
        return c
    }

    var csvHeader: [String] { columns.map(\.title) }

    func csvRows() -> [[String]] {
        let cols = columns
        return rows().map { row in cols.map { $0.value(row) } }
    }

    func csvData() -> Data { CSV.data(header: csvHeader, rows: csvRows()) }

    // MARK: Shared field text

    func parameterLines(_ row: ExportRow) -> [String] {
        let values = assessment.parameterValueMap(frameworkID: row.framework.id)
        return row.requirement.editableParameters.compactMap { p -> String? in
            guard let v = values[p.id], !v.isEmpty else { return nil }
            return "\(p.placeholder.prefix(1).uppercased() + p.placeholder.dropFirst()): \(v)"
        }
    }

    func evidenceLines(_ row: ExportRow) -> [String] {
        (row.response?.sortedEvidence ?? []).map { e in
            switch e.kind {
            case .note:
                return options.notes && !e.text.isEmpty ? "Note: \(e.title) — \(e.text)" : "Note: \(e.title)"
            case .link:
                return "Link: \(e.title) (\(e.urlString))"
            case .file:
                return "File: \(e.title)"
            }
        }
    }

    // MARK: JSON

    func jsonData() throws -> Data {
        let all = rows()
        let document = ExportDocument(
            exportedAt: .now,
            appVersion: BackupService.appVersion,
            requirementSelection: options.requirements.rawValue,
            included: options.includedFieldNames,
            assessment: .init(
                name: assessment.name,
                organization: assessment.organization.isEmpty ? nil : assessment.organization,
                notes: options.notes && !assessment.notes.isEmpty ? assessment.notes : nil,
                createdAt: assessment.createdAt,
                updatedAt: assessment.updatedAt,
                csfCurrentTier: options.profile ? assessment.csfCurrentTier : nil,
                csfTargetTier: options.profile ? assessment.csfTargetTier : nil),
            frameworks: frameworks.map { fw in
                let scope = assessment.scope(for: fw.id)
                let progress = ProgressSummary(ids: fw.requirementsInScope(scope).map(\.id),
                                               statuses: assessment.statusMap(frameworkID: fw.id))
                return .init(
                    id: fw.id, name: fw.document.shortName, title: fw.document.title,
                    publication: fw.document.publicationId, version: fw.document.version,
                    scope: ScopeDescription.short(scope, framework: fw),
                    progress: .init(applicable: progress.applicable, implemented: progress.implemented,
                                    inProgress: progress.inProgress, notStarted: progress.notStarted,
                                    notApplicable: progress.notApplicable,
                                    percentImplemented: Int((progress.fractionImplemented * 100).rounded())),
                    requirements: all.filter { $0.framework.id == fw.id }.map(jsonRequirement))
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    private func jsonRequirement(_ row: ExportRow) -> ExportDocument.RequirementEntry {
        let r = row.requirement
        let fw = row.framework
        let response = row.response
        let values = assessment.parameterValueMap(frameworkID: fw.id)
        func text(_ s: String?) -> String? { (s?.isEmpty ?? true) ? nil : s }
        let isProfile = !fw.document.tiers.isEmpty

        var parameters: [ExportDocument.ParameterEntry]?
        if options.parameters {
            let entries = r.editableParameters.compactMap { (p: Parameter) -> ExportDocument.ParameterEntry? in
                guard let v = values[p.id], !v.isEmpty else { return nil }
                return ExportDocument.ParameterEntry(id: p.displayLabel ?? p.id, description: p.placeholder, value: v)
            }
            parameters = entries.isEmpty ? nil : entries
        }

        var evidence: [ExportDocument.EvidenceEntry]?
        if options.evidence {
            let entries = (response?.sortedEvidence ?? []).map { (e: EvidenceItem) -> ExportDocument.EvidenceEntry in
                ExportDocument.EvidenceEntry(
                    kind: e.kind.rawValue, title: e.title,
                    text: options.notes && e.kind == .note ? text(e.text) : nil,
                    url: e.kind == .link ? text(e.urlString) : nil,
                    fileName: e.kind == .file ? e.originalFileName : nil,
                    added: e.createdAt.formatted(Self.dateFormat))
            }
            evidence = entries.isEmpty ? nil : entries
        }

        let reason: String? = options.notApplicableReasons && row.status == .notApplicable ? text(response?.notApplicableReason) : nil
        let owner: String? = options.ownership ? text(response?.owner) : nil
        let target: String? = options.ownership ? response?.targetDate.map { $0.formatted(Self.dateFormat) } : nil
        let notes: String? = options.notes ? text(response?.notes) : nil
        let applied: String? = response?.appliedFromRequirementID.map { "\(response?.appliedFromFrameworkID ?? "") \($0)" }
        let inProfile: Bool? = options.profile && isProfile ? (response?.inTargetProfile ?? true) : nil
        let priority: String? = options.profile && isProfile ? response?.priority?.title : nil
        let updated: String? = response.map { $0.updatedAt.formatted(Self.dateFormat) }
        let statement: String? = options.nistText ? StatementText.plain(r, in: fw, values: options.parameters ? values : [:]) : nil
        let baselines: [String]? = r.baselines.isEmpty ? nil : r.baselines.compactMap { fw.baseline($0)?.title }
        let group: String? = fw.group(r.groupId).map { "\($0.displayId) \($0.title)" }

        return ExportDocument.RequirementEntry(
            id: r.displayId, title: r.title, type: fw.kind(r.kind)?.singular ?? r.kind, group: group,
            inScope: row.inScope, baselines: baselines, status: row.status.title,
            notApplicableReason: reason, owner: owner, targetDate: target, notes: notes,
            organizationDefinedValues: parameters, evidence: evidence, appliedFrom: applied,
            csfTargetProfile: inProfile, csfPriority: priority, lastUpdated: updated, requirementText: statement)
    }

    // MARK: Files

    func file() throws -> URL {
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let scope = frameworks.count == 1 ? " \(frameworks[0].document.shortName)" : ""
        let base = "\(BackupService.safeFileName(assessment.name))\(scope)"
        switch options.format {
        case .csv:
            return try ExportFiles.write(csvData(), named: "\(base) \(stamp).csv")
        case .json:
            return try ExportFiles.write(try jsonData(), named: "\(base) \(stamp).json")
        case .pdf:
            return try PDFReport(assessment: assessment, frameworks: frameworks, graph: graph, options: options).render()
        }
    }
}

/// The JSON export's shape. Optional fields are omitted when empty or left out by the user.
struct ExportDocument: Encodable {
    var format = "frameworkapp.assessment-export"
    var formatVersion = 1
    let exportedAt: Date
    let appVersion: String
    let requirementSelection: String
    let included: [String]
    let assessment: AssessmentInfo
    let frameworks: [FrameworkEntry]

    struct AssessmentInfo: Encodable {
        let name: String
        let organization: String?
        let notes: String?
        let createdAt: Date
        let updatedAt: Date
        let csfCurrentTier: Int?
        let csfTargetTier: Int?
    }

    struct Progress: Encodable {
        let applicable, implemented, inProgress, notStarted, notApplicable, percentImplemented: Int
    }

    struct FrameworkEntry: Encodable {
        let id, name, title, publication, version, scope: String
        let progress: Progress
        let requirements: [RequirementEntry]
    }

    struct ParameterEntry: Encodable {
        let id, description, value: String
    }

    struct EvidenceEntry: Encodable {
        let kind, title: String
        let text, url, fileName: String?
        let added: String
    }

    struct RequirementEntry: Encodable {
        let id, title, type: String
        let group: String?
        let inScope: Bool
        let baselines: [String]?
        let status: String
        let notApplicableReason, owner, targetDate, notes: String?
        let organizationDefinedValues: [ParameterEntry]?
        let evidence: [EvidenceEntry]?
        let appliedFrom: String?
        let csfTargetProfile: Bool?
        let csfPriority: String?
        let lastUpdated: String?
        let requirementText: String?
    }
}
