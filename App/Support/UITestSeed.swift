#if DEBUG
import Foundation
import FrameworkKit
import SwiftData

/// Data for UI tests and screenshots only. Compiled into debug builds, used only with `-uiSeed`
/// against an in-memory store, never shipped.
@MainActor
enum UITestSeed {
    /// Password for the sample file the `import` route opens.
    static let importPassword = "harbor-clinic"

    static func apply(_ scenario: String, context: ModelContext, library: ContentLibrary) -> Assessment? {
        guard scenario == "sample" else { return nil }
        let service = AssessmentService(context: context)
        let a = service.createAssessment(
            name: "Harbor Clinic 2026",
            organization: "Harbor Family Clinic",
            frameworkIDs: library.frameworkOrder,
            scopes: ["sp800-53r5": ScopeSelection(baselineID: "low")]
        )
        let csf = "csf-2.0"
        let answers: [(String, RequirementStatus)] = [
            ("GV.OC-01", .implemented), ("GV.OC-02", .implemented), ("GV.OC-03", .inProgress),
            ("GV.OC-04", .implemented), ("GV.OC-05", .implemented), ("GV.RM-01", .inProgress),
            ("ID.AM-01", .implemented), ("ID.AM-02", .inProgress), ("PR.AA-01", .inProgress),
            ("PR.AA-03", .implemented), ("PR.DS-01", .implemented),
        ]
        for (id, status) in answers {
            service.setStatus(status, for: RequirementRef(frameworkID: csf, requirementID: id), in: a)
        }
        service.setStatus(.notApplicable, for: RequirementRef(frameworkID: csf, requirementID: "PR.PS-06"), in: a,
                          reason: "The clinic does not develop software.")
        let ref = RequirementRef(frameworkID: csf, requirementID: "GV.OC-03")
        service.update(ref, in: a) {
            $0.owner = "Practice manager"
            $0.notes = "Health privacy obligations are tracked. Payment card terms in the processor contract still need review."
            $0.targetDate = Calendar.current.date(byAdding: .day, value: 45, to: Date())
        }
        service.addNote(title: "Regulatory inventory, January", text: "List of applicable privacy rules reviewed with counsel.",
                        to: ref, in: a)
        if let url = URL(string: "https://intranet.example.org/policies/privacy") {
            service.addLink(title: "Privacy policy", url: url, to: ref, in: a)
        }
        // CSF Target Profile, priorities, tiers, and an overdue item for the dashboards.
        let day: TimeInterval = 86_400
        for id in ["PR.AA-05", "PR.DS-02", "DE.CM-01"] {
            service.setPriority(.high, for: RequirementRef(frameworkID: csf, requirementID: id), in: a)
        }
        service.setPriority(.medium, for: RequirementRef(frameworkID: csf, requirementID: "RS.MA-01"), in: a)
        service.setInTargetProfile(false, for: RequirementRef(frameworkID: csf, requirementID: "GV.SC-10"), in: a)
        service.update(RequirementRef(frameworkID: csf, requirementID: "ID.AM-02"), in: a) {
            $0.targetDate = Date().addingTimeInterval(-10 * day)
            $0.owner = "IT contractor"
        }
        a.csfCurrentTier = 2
        a.csfTargetTier = 3
        for id in ["ac-1", "ac-2", "at-1", "at-2", "ia-2", "ia-2.1", "cp-9"] {
            service.setStatus(.implemented, for: RequirementRef(frameworkID: "sp800-53r5", requirementID: id), in: a)
        }
        for id in ["au-2", "cm-2", "ra-5"] {
            service.setStatus(.inProgress, for: RequirementRef(frameworkID: "sp800-53r5", requirementID: id), in: a)
        }
        service.setStatus(.implemented, for: RequirementRef(frameworkID: "sp800-171r3", requirementID: "03.01.01"), in: a)
        service.update(RequirementRef(frameworkID: "sp800-171r3", requirementID: "03.01.01"), in: a) {
            $0.notes = "Accounts are requested through the help desk and reviewed each quarter."
        }
        service.setParameter("A.03.01.01.ODP.01", frameworkID: "sp800-171r3", value: "90 days", in: a)
        return a
    }
}
#endif
