import Foundation

// MARK: - Facts about one answer (supplied by the app from its store)

public enum ProfilePriority: String, Sendable, Hashable, Codable, CaseIterable, Identifiable, Comparable {
    case high, medium, low

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    var rank: Int { self == .high ? 0 : self == .medium ? 1 : 2 }
    public static func < (a: ProfilePriority, b: ProfilePriority) -> Bool { a.rank < b.rank }
}

/// What the store knows about one requirement's answer.
public struct ResponseFacts: Sendable, Hashable {
    public var status: RequirementStatus
    public var targetDate: Date?
    /// CSF Target Profile: whether the outcome is part of the target (default true).
    public var inTargetProfile: Bool
    public var priority: ProfilePriority?

    public init(status: RequirementStatus = .notStarted, targetDate: Date? = nil,
                inTargetProfile: Bool = true, priority: ProfilePriority? = nil) {
        self.status = status
        self.targetDate = targetDate
        self.inTargetProfile = inTargetProfile
        self.priority = priority
    }
}

// MARK: - Next steps

/// One open requirement ranked by `NextStepsEngine`, with the reasons it ranks where it does.
public struct NextStep: Sendable, Hashable, Identifiable {
    public enum Reason: Sendable, Hashable {
        case overdue(Date)
        case inProgress
        case dueSoon(Date)
        case priority(ProfilePriority)
        case foundational
        case coversMapped(Int)
    }

    public let ref: RequirementRef
    public let status: RequirementStatus
    public let reasons: [Reason]
    public var id: RequirementRef { ref }
}

/// Ranks open requirements across enabled frameworks. The order is deterministic:
///
/// 1. Overdue target dates first.
/// 2. In progress before not started (finish what was started).
/// 3. CSF Target Profile priority: high, medium, low, then unprioritized.
/// 4. Foundational items first: policy-and-procedures requirements and CSF Govern outcomes.
/// 5. Reuse: how many open, NIST-mapped requirements in other enabled frameworks one answer touches.
/// 6. Nearest target date, then framework order and document order.
public enum NextStepsEngine {
    public static let dueSoonWindow: TimeInterval = 14 * 24 * 3600

    public static func rank(
        frameworks: [Framework],
        scopes: [String: ScopeSelection],
        facts: [RequirementRef: ResponseFacts],
        graph: MappingGraph?,
        now: Date = Date()
    ) -> [NextStep] {
        let enabled = Set(frameworks.map(\.id))
        struct Candidate {
            let step: NextStep
            let overdue: Bool
            let inProgress: Bool
            let priorityRank: Int
            let foundational: Bool
            let reuse: Int
            let date: Date
            let frameworkIndex: Int
            let position: Int
        }
        var candidates: [Candidate] = []

        for (fIndex, fw) in frameworks.enumerated() {
            let scope = scopes[fw.id] ?? .fullCatalog
            for r in fw.requirementsInScope(scope) {
                let ref = RequirementRef(frameworkID: fw.id, requirementID: r.id)
                let f = facts[ref] ?? ResponseFacts()
                guard f.status == .notStarted || f.status == .inProgress else { continue }
                // CSF outcomes left out of the Target Profile are not next steps.
                if !fw.document.tiers.isEmpty && !f.inTargetProfile { continue }

                var reasons: [NextStep.Reason] = []
                let overdue = f.targetDate.map { $0 < now } ?? false
                if let d = f.targetDate {
                    if overdue { reasons.append(.overdue(d)) } else if d.timeIntervalSince(now) <= dueSoonWindow { reasons.append(.dueSoon(d)) }
                }
                if f.status == .inProgress { reasons.append(.inProgress) }
                if let p = f.priority { reasons.append(.priority(p)) }
                let foundational = isFoundational(r, in: fw)
                if foundational { reasons.append(.foundational) }
                let reuse = graph.map { openMappedCount(from: ref, graph: $0, enabled: enabled, facts: facts) } ?? 0
                if reuse > 0 { reasons.append(.coversMapped(reuse)) }

                candidates.append(Candidate(
                    step: NextStep(ref: ref, status: f.status, reasons: reasons),
                    overdue: overdue,
                    inProgress: f.status == .inProgress,
                    priorityRank: f.priority?.rank ?? 3,
                    foundational: foundational,
                    reuse: reuse,
                    date: f.targetDate ?? .distantFuture,
                    frameworkIndex: fIndex,
                    position: fw.position(of: r.id) ?? 0
                ))
            }
        }

        return candidates.sorted { a, b in
            if a.overdue != b.overdue { return a.overdue }
            if a.inProgress != b.inProgress { return a.inProgress }
            if a.priorityRank != b.priorityRank { return a.priorityRank < b.priorityRank }
            if a.foundational != b.foundational { return a.foundational }
            if a.reuse != b.reuse { return a.reuse > b.reuse }
            if a.date != b.date { return a.date < b.date }
            if a.frameworkIndex != b.frameworkIndex { return a.frameworkIndex < b.frameworkIndex }
            return a.position < b.position
        }.map(\.step)
    }

    /// Policy-and-procedures requirements, and CSF Govern outcomes, set up everything else.
    public static func isFoundational(_ r: Requirement, in framework: Framework) -> Bool {
        if r.title == "Policy and Procedures" { return true }
        if !framework.document.tiers.isEmpty {
            let top = framework.ancestors(ofGroup: r.groupId).first?.id ?? r.groupId
            return top == "GV"
        }
        return false
    }

    static func openMappedCount(from ref: RequirementRef, graph: MappingGraph, enabled: Set<String>,
                                facts: [RequirementRef: ResponseFacts]) -> Int {
        let targets = Set(graph.links(from: ref, enabledFrameworks: enabled).map(\.target))
        return targets.filter { t in
            let s = facts[t]?.status ?? .notStarted
            return s == .notStarted || s == .inProgress
        }.count
    }
}

// MARK: - CSF Organizational Profile

/// Current vs Target for one CSF Function.
public struct ProfileGroupSummary: Sendable, Hashable, Identifiable {
    public let groupID: String
    public let title: String
    /// Outcomes in the Target Profile.
    public let targeted: Int
    /// Targeted outcomes currently implemented.
    public let achieved: Int
    /// Targeted outcomes in progress.
    public let inProgress: Int
    /// Outcomes excluded from the Target Profile or marked not applicable.
    public let excluded: Int

    public var id: String { groupID }
    public var gap: Int { targeted - achieved }
    public var fractionAchieved: Double { targeted == 0 ? 0 : Double(achieved) / Double(targeted) }
}

public enum ProfileAnalysis {
    /// Current vs Target per top-level group (CSF Function).
    public static func summarize(_ framework: Framework, facts: [String: ResponseFacts]) -> [ProfileGroupSummary] {
        framework.groups.map { group in
            var targeted = 0, achieved = 0, inProgress = 0, excluded = 0
            for r in framework.requirements(inGroup: group.id) {
                let f = facts[r.id] ?? ResponseFacts()
                if !f.inTargetProfile || f.status == .notApplicable {
                    excluded += 1
                    continue
                }
                targeted += 1
                if f.status == .implemented { achieved += 1 }
                if f.status == .inProgress { inProgress += 1 }
            }
            return ProfileGroupSummary(groupID: group.id, title: group.title, targeted: targeted,
                                       achieved: achieved, inProgress: inProgress, excluded: excluded)
        }
    }

    /// Targeted outcomes not yet implemented, highest priority first, then document order.
    public static func gaps(_ framework: Framework, facts: [String: ResponseFacts]) -> [Requirement] {
        framework.requirements.filter { r in
            let f = facts[r.id] ?? ResponseFacts()
            return f.inTargetProfile && f.status != .implemented && f.status != .notApplicable
        }.sorted { a, b in
            let pa = facts[a.id]?.priority?.rank ?? 3, pb = facts[b.id]?.priority?.rank ?? 3
            if pa != pb { return pa < pb }
            return a.sortKey < b.sortKey
        }
    }
}

// MARK: - Progress by group and baseline

public struct GroupProgress: Sendable, Hashable, Identifiable {
    public let group: RequirementGroup
    public let progress: ProgressSummary
    public var id: String { group.id }
}

extension Framework {
    /// Progress for each top-level group (CSF Function or SP 800-53 / 800-171 family) within scope.
    public func progressByTopGroup(scope: ScopeSelection, statuses: [String: RequirementStatus]) -> [GroupProgress] {
        let inScope = Set(requirementsInScope(scope).map(\.id))
        return groups.map { g in
            let ids = requirements(inGroup: g.id).map(\.id).filter(inScope.contains)
            return GroupProgress(group: g, progress: ProgressSummary(ids: ids, statuses: statuses))
        }.filter { $0.progress.total > 0 }
    }

    /// Progress against each SP 800-53B baseline, regardless of the selected scope.
    public func progressByBaseline(statuses: [String: RequirementStatus]) -> [(baseline: Baseline, progress: ProgressSummary)] {
        document.baselines.map { b in
            let ids = requirements.filter { $0.baselines.contains(b.id) }.map(\.id)
            return (b, ProgressSummary(ids: ids, statuses: statuses))
        }
    }
}
