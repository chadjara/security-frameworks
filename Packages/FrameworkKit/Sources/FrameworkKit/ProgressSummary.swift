import Foundation

/// Status counts for a set of requirements.
///
/// Not applicable items are excluded from the denominator. A set where every item is not
/// applicable counts as complete.
public struct ProgressSummary: Sendable, Hashable {
    public var notStarted = 0
    public var inProgress = 0
    public var implemented = 0
    public var notApplicable = 0

    public init() {}

    public init(statuses: some Sequence<RequirementStatus>) {
        for s in statuses { add(s) }
    }

    /// Counts `ids`, treating any requirement without a recorded status as not started.
    public init(ids: some Sequence<String>, statuses: [String: RequirementStatus]) {
        for id in ids { add(statuses[id] ?? .notStarted) }
    }

    public mutating func add(_ status: RequirementStatus) {
        switch status {
        case .notStarted: notStarted += 1
        case .inProgress: inProgress += 1
        case .implemented: implemented += 1
        case .notApplicable: notApplicable += 1
        }
    }

    public var total: Int { notStarted + inProgress + implemented + notApplicable }
    public var applicable: Int { total - notApplicable }
    /// Items that have an answer other than "not started".
    public var answered: Int { total - notStarted }

    /// Implemented share of applicable items, 0...1.
    public var fractionImplemented: Double {
        guard total > 0 else { return 0 }
        guard applicable > 0 else { return 1 }
        return Double(implemented) / Double(applicable)
    }

    /// Every item is implemented or not applicable.
    public var isComplete: Bool { total > 0 && notStarted == 0 && inProgress == 0 }

    public func count(_ status: RequirementStatus) -> Int {
        switch status {
        case .notStarted: return notStarted
        case .inProgress: return inProgress
        case .implemented: return implemented
        case .notApplicable: return notApplicable
        }
    }

    public static func + (a: ProgressSummary, b: ProgressSummary) -> ProgressSummary {
        var out = a
        out.notStarted += b.notStarted
        out.inProgress += b.inProgress
        out.implemented += b.implemented
        out.notApplicable += b.notApplicable
        return out
    }
}
