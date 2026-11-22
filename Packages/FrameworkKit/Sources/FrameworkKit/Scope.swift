import Foundation

/// Which requirements of a framework an assessment covers.
///
/// Frameworks without baselines (CSF 2.0, SP 800-171) are always fully in scope. For SP 800-53 the
/// user picks one base baseline (Low, Moderate, or High), optionally adds additive baselines
/// (Privacy), and may add individual requirements by hand.
public struct ScopeSelection: Sendable, Hashable, Codable {
    public var baselineID: String?
    public var additiveBaselineIDs: Set<String>
    public var addedRequirementIDs: Set<String>

    public init(baselineID: String? = nil, additiveBaselineIDs: Set<String> = [], addedRequirementIDs: Set<String> = []) {
        self.baselineID = baselineID
        self.additiveBaselineIDs = additiveBaselineIDs
        self.addedRequirementIDs = addedRequirementIDs
    }

    /// Every requirement in the framework.
    public static let fullCatalog = ScopeSelection()

    public var usesBaselines: Bool { baselineID != nil || !additiveBaselineIDs.isEmpty }
}

extension Framework {
    public func isInScope(_ requirement: Requirement, selection: ScopeSelection) -> Bool {
        guard hasBaselines, selection.usesBaselines else { return true }
        if selection.addedRequirementIDs.contains(requirement.id) { return true }
        if let base = selection.baselineID, requirement.baselines.contains(base) { return true }
        return requirement.baselines.contains { selection.additiveBaselineIDs.contains($0) }
    }

    public func requirementsInScope(_ selection: ScopeSelection) -> [Requirement] {
        guard hasBaselines, selection.usesBaselines else { return requirements }
        return requirements.filter { isInScope($0, selection: selection) }
    }

    /// Requirements outside the selection that the user could add manually.
    public func requirementsOutOfScope(_ selection: ScopeSelection) -> [Requirement] {
        guard hasBaselines, selection.usesBaselines else { return [] }
        return requirements.filter { !isInScope($0, selection: selection) }
    }
}
