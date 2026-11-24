import FrameworkKit
import Foundation

/// Rows and summaries shared by the CSV export and the PDF report.
@MainActor
struct ReportBuilder {
    let assessment: Assessment
    let frameworks: [Framework]

    static let csvHeader = [
        "Framework", "Requirement ID", "Title", "Type", "Group", "In scope", "Baselines", "Status",
        "Not applicable reason", "Owner", "Target date", "Notes", "Organization-defined values", "Evidence items",
        "Applied from", "CSF target profile", "CSF priority", "Last updated",
    ]

    /// One CSV row per requirement (in scope first, then everything else), across the given frameworks.
    func csvRows() -> [[String]] {
        var rows: [[String]] = []
        let dateFormat = Date.ISO8601FormatStyle().year().month().day()
        for fw in frameworks {
            let scope = assessment.scope(for: fw.id)
            let values = assessment.parameterValueMap(frameworkID: fw.id)
            for r in fw.requirements {
                let ref = RequirementRef(frameworkID: fw.id, requirementID: r.id)
                let response = assessment.response(for: ref)
                let group = fw.group(r.groupId)
                let params = r.editableParameters.compactMap { p -> String? in
                    guard let v = values[p.id], !v.isEmpty else { return nil }
                    return "\(p.placeholder): \(v)"
                }
                rows.append([
                    fw.document.shortName,
                    r.displayId,
                    r.title,
                    fw.kind(r.kind)?.singular ?? r.kind,
                    group.map { "\($0.displayId) \($0.title)" } ?? "",
                    fw.isInScope(r, selection: scope) ? "Yes" : "No",
                    r.baselines.compactMap { fw.baseline($0)?.title }.joined(separator: "; "),
                    (response?.status ?? .notStarted).title,
                    response?.notApplicableReason ?? "",
                    response?.owner ?? "",
                    response?.targetDate.map { $0.formatted(dateFormat) } ?? "",
                    response?.notes ?? "",
                    params.joined(separator: "; "),
                    "\(response?.evidence.count ?? 0)",
                    response?.appliedFromRequirementID.map { "\(response?.appliedFromFrameworkID ?? "") \($0)" } ?? "",
                    fw.document.tiers.isEmpty ? "" : ((response?.inTargetProfile ?? true) ? "Included" : "Excluded"),
                    response?.priority?.title ?? "",
                    response.map { $0.updatedAt.formatted(dateFormat) } ?? "",
                ])
            }
        }
        return rows
    }

    func csvFile() throws -> URL {
        let data = CSV.data(header: Self.csvHeader, rows: csvRows())
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        return try ExportFiles.write(data, named: "\(BackupService.safeFileName(assessment.name)) \(stamp).csv")
    }
}
