import Foundation

/// A loaded framework with lookup indexes built once at load time.
public struct Framework: Sendable, Identifiable {
    public let document: FrameworkDocument
    private let requirementPositions: [String: Int]
    private let childIDs: [String: [String]]
    private let groupsByID: [String: RequirementGroup]
    private let groupAncestors: [String: [String]]
    private let leafGroupOrder: [String]
    private let parameterScopes: [String: [String: Parameter]]
    private let withdrawnByID: [String: WithdrawnRequirement]

    public var id: String { document.id }
    public var requirements: [Requirement] { document.requirements }
    public var groups: [RequirementGroup] { document.groups }
    public var hasBaselines: Bool { !document.baselines.isEmpty }

    public init(document: FrameworkDocument) {
        self.document = document

        var positions: [String: Int] = [:]
        var children: [String: [String]] = [:]
        positions.reserveCapacity(document.requirements.count)
        for (i, r) in document.requirements.enumerated() {
            positions[r.id] = i
            if let parent = r.parentId { children[parent, default: []].append(r.id) }
        }
        requirementPositions = positions
        childIDs = children

        var byID: [String: RequirementGroup] = [:]
        var ancestors: [String: [String]] = [:]
        var leaves: [String] = []
        func walk(_ groups: [RequirementGroup], path: [String]) {
            for g in groups {
                byID[g.id] = g
                ancestors[g.id] = path
                if g.isLeaf { leaves.append(g.id) }
                walk(g.groups, path: path + [g.id])
            }
        }
        walk(document.groups, path: [])
        groupsByID = byID
        groupAncestors = ancestors
        leafGroupOrder = leaves

        // Parameters resolve within a family tree: the base control plus its enhancements.
        var scopes: [String: [String: Parameter]] = [:]
        for r in document.requirements {
            let root = r.parentId ?? r.id
            for p in r.parameters {
                scopes[root, default: [:]][p.id] = p
                if let alt = p.altId { scopes[root, default: [:]][alt] = p }
            }
        }
        parameterScopes = scopes
        withdrawnByID = Dictionary(document.withdrawn.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Lookup

    public func requirement(_ id: String) -> Requirement? {
        requirementPositions[id].map { document.requirements[$0] }
    }

    public func position(of id: String) -> Int? { requirementPositions[id] }

    public func withdrawnRequirement(_ id: String) -> WithdrawnRequirement? { withdrawnByID[id] }

    public func children(of id: String) -> [Requirement] {
        (childIDs[id] ?? []).compactMap(requirement)
    }

    public func group(_ id: String) -> RequirementGroup? { groupsByID[id] }

    /// Ancestor groups of a group, outermost first.
    public func ancestors(ofGroup id: String) -> [RequirementGroup] {
        (groupAncestors[id] ?? []).compactMap { groupsByID[$0] }
    }

    public var leafGroups: [RequirementGroup] { leafGroupOrder.compactMap { groupsByID[$0] } }

    /// All requirements under a group (any depth), including enhancements, in document order.
    public func requirements(inGroup id: String) -> [Requirement] {
        guard let group = groupsByID[id] else { return [] }
        let leafIDs = Set(leafIDs(under: group))
        return document.requirements.filter { leafIDs.contains($0.groupId) }
    }

    private func leafIDs(under group: RequirementGroup) -> [String] {
        group.isLeaf ? [group.id] : group.groups.flatMap { leafIDs(under: $0) }
    }

    public func kind(_ id: String) -> RequirementKind? { document.kinds.first { $0.id == id } }

    public func baseline(_ id: String) -> Baseline? { document.baselines.first { $0.id == id } }

    /// Parameters that `{{param:…}}` tokens in this requirement may refer to.
    public func parameterScope(for requirement: Requirement) -> [String: Parameter] {
        parameterScopes[requirement.parentId ?? requirement.id] ?? [:]
    }
}
