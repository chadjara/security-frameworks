import FrameworkKit
import Foundation

/// File formats for an assessment export. The encrypted backup is separate: it always contains everything.
enum ExportFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case pdf, csv, json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF Report"
        case .csv: return "Spreadsheet"
        case .json: return "Data File"
        }
    }

    var detail: String {
        switch self {
        case .pdf: return "Formatted for reading, printing, and sharing with leadership or an auditor."
        case .csv: return "CSV, one row per requirement. Opens in Numbers, Excel, and Google Sheets."
        case .json: return "Structured JSON for importing into other tools or your own records."
        }
    }

    var systemImage: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        }
    }

    var actionTitle: String {
        switch self {
        case .pdf: return "Create PDF Report"
        case .csv: return "Create Spreadsheet"
        case .json: return "Create Data File"
        }
    }

    var fileExtension: String { rawValue }
}

/// Which requirements an export lists.
enum ExportRequirementFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case inScope, open, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inScope: return "In scope"
        case .open: return "Open items only"
        case .all: return "Entire framework"
        }
    }

    var detail: String {
        switch self {
        case .inScope: return "Every requirement in this assessment's scope."
        case .open: return "In-scope requirements that are not started or in progress."
        case .all: return "Every requirement in the framework, including those outside your scope."
        }
    }
}

/// Information a user can leave out of an export. Status, ID, and title are always included.
enum ExportField: String, CaseIterable, Identifiable, Sendable {
    case ownership, notes, notApplicableReasons, parameters, evidence, profile, nistText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ownership: return "Owners and target dates"
        case .notes: return "Notes"
        case .notApplicableReasons: return "Not applicable reasons"
        case .parameters: return "Organization-defined values"
        case .evidence: return "Evidence list"
        case .profile: return "CSF profile and priority"
        case .nistText: return "NIST requirement text"
        }
    }

    var detail: String {
        switch self {
        case .ownership: return "Who is responsible and when it is due."
        case .notes: return "Requirement notes and the text of note evidence."
        case .notApplicableReasons: return "Why a requirement was marked not applicable."
        case .parameters: return "Values your organization chose, such as review frequencies."
        case .evidence: return "Titles of photos, files, links, and notes. Files themselves are not included."
        case .profile: return "Target profile membership and priority for CSF outcomes."
        case .nistText: return "The full requirement statement. Makes the export much longer."
        }
    }

    var systemImage: String {
        switch self {
        case .ownership: return "person.crop.circle"
        case .notes: return "text.alignleft"
        case .notApplicableReasons: return "minus.circle"
        case .parameters: return "slider.horizontal.3"
        case .evidence: return "paperclip"
        case .profile: return "target"
        case .nistText: return "text.book.closed"
        }
    }

    var keyPath: WritableKeyPath<ExportOptions, Bool> {
        switch self {
        case .ownership: return \.ownership
        case .notes: return \.notes
        case .notApplicableReasons: return \.notApplicableReasons
        case .parameters: return \.parameters
        case .evidence: return \.evidence
        case .profile: return \.profile
        case .nistText: return \.nistText
        }
    }
}

/// What to put in an export. Remembered between exports (without the framework selection, which is per assessment).
struct ExportOptions: Codable, Equatable, Sendable {
    var format: ExportFormat = .pdf
    var requirements: ExportRequirementFilter = .inScope

    // PDF sections.
    var summary = true
    var nextSteps = true
    var requirementDetails = true

    // Requirement fields.
    var ownership = true
    var notes = true
    var notApplicableReasons = true
    var parameters = true
    var evidence = true
    var profile = true
    var nistText = false

    static let everything: ExportOptions = {
        var o = ExportOptions()
        o.nistText = true
        o.requirements = .inScope
        return o
    }()

    func includes(_ field: ExportField) -> Bool { self[keyPath: field.keyPath] }

    /// Whether the PDF would contain anything beyond its cover.
    var pdfHasContent: Bool { summary || nextSteps || requirementDetails }

    /// Field names included, for the export's own record of what it contains.
    var includedFieldNames: [String] { ExportField.allCases.filter(includes).map(\.rawValue) }

    static func decode(_ data: Data) -> ExportOptions {
        (try? JSONDecoder().decode(ExportOptions.self, from: data)) ?? ExportOptions()
    }

    var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }
}

/// One requirement chosen for an export, with the assessment's answer.
@MainActor
struct ExportRow {
    let framework: Framework
    let requirement: Requirement
    let response: RequirementResponse?
    let inScope: Bool

    var status: RequirementStatus { response?.status ?? .notStarted }
    var ref: RequirementRef { RequirementRef(frameworkID: framework.id, requirementID: requirement.id) }
}

extension ExportOptions {
    /// Whether a requirement belongs in the export under the requirement filter.
    func shouldInclude(inScope: Bool, status: RequirementStatus) -> Bool {
        switch requirements {
        case .all: return true
        case .inScope: return inScope
        case .open: return inScope && (status == .notStarted || status == .inProgress)
        }
    }
}

/// Plain-text rendering of requirement statements, with organization-defined values filled in.
enum StatementText {
    static func plain(_ requirement: Requirement, in framework: Framework, values: [String: String]) -> String {
        let scope = framework.parameterScope(for: requirement)
        var lines: [String] = []
        func walk(_ items: [TextItem], depth: Int) {
            for item in items {
                let text = item.text.map { ParameterText.plain($0, parameters: scope, values: values) } ?? ""
                let line = [item.label, text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                if !line.isEmpty { lines.append(String(repeating: "    ", count: depth) + line) }
                walk(item.items, depth: depth + 1)
            }
        }
        walk(requirement.statement, depth: 0)
        return lines.joined(separator: "\n")
    }
}
