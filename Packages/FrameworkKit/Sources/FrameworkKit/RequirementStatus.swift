import Foundation

/// Implementation status recorded for a requirement.
public enum RequirementStatus: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case notStarted
    case inProgress
    case implemented
    case notApplicable

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notStarted: return "Not started"
        case .inProgress: return "In progress"
        case .implemented: return "Implemented"
        case .notApplicable: return "Not applicable"
        }
    }

    /// Not applicable must always carry a reason.
    public var requiresReason: Bool { self == .notApplicable }

    /// Whether the requirement counts toward progress (not applicable items are excluded).
    public var isApplicable: Bool { self != .notApplicable }
}
