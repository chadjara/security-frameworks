import Foundation

/// `index.json`: a lightweight summary of every bundled framework and mapping, read at launch.
public struct ContentIndex: Sendable, Hashable, Codable {
    public let schemaVersion: Int
    public let contentVersion: String
    public let frameworks: [FrameworkIndexEntry]
    public let mappings: [MappingIndexEntry]

    public init(schemaVersion: Int, contentVersion: String, frameworks: [FrameworkIndexEntry], mappings: [MappingIndexEntry]) {
        self.schemaVersion = schemaVersion
        self.contentVersion = contentVersion
        self.frameworks = frameworks
        self.mappings = mappings
    }
}

public struct FrameworkIndexEntry: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let file: String
    public let shortName: String
    public let title: String
    public let publicationId: String
    public let version: String
    public let summary: FrameworkSummary?
    public let kinds: [RequirementKind]
    public let groupLevels: [GroupLevel]
    public let baselines: [Baseline]
    public let notices: [Notice]
    public let counts: FrameworkCounts

    enum CodingKeys: String, CodingKey {
        case id, file, shortName, title, publicationId, version, summary, kinds, groupLevels, baselines, notices, counts
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        file = try c.decode(String.self, forKey: .file)
        shortName = try c.decode(String.self, forKey: .shortName)
        title = try c.decode(String.self, forKey: .title)
        publicationId = try c.decode(String.self, forKey: .publicationId)
        version = try c.decode(String.self, forKey: .version)
        summary = try c.decodeIfPresent(FrameworkSummary.self, forKey: .summary)
        kinds = try c.decode([RequirementKind].self, forKey: .kinds)
        groupLevels = try c.decode([GroupLevel].self, forKey: .groupLevels)
        baselines = try c.decodeIfPresent([Baseline].self, forKey: .baselines) ?? []
        notices = try c.decodeIfPresent([Notice].self, forKey: .notices) ?? []
        counts = try c.decode(FrameworkCounts.self, forKey: .counts)
    }

    /// Builds an entry for a framework file that is not listed in `index.json`.
    public init(document: FrameworkDocument, file: String) {
        id = document.id
        self.file = file
        shortName = document.shortName
        title = document.title
        publicationId = document.publicationId
        version = document.version
        summary = document.summary
        kinds = document.kinds
        groupLevels = document.groupLevels
        baselines = document.baselines
        notices = document.notices
        counts = FrameworkCounts(document: document)
    }
}

public struct FrameworkCounts: Sendable, Hashable, Codable {
    public let requirements: Int
    public let byKind: [String: Int]
    /// Number of groups at each depth, e.g. `[6, 22]` for CSF functions and categories.
    public let groups: [Int]
    public let withdrawn: Int
    public let parameters: Int
    public let withEditorial: Int
    public let byBaseline: [String: [String: Int]]?

    public init(document: FrameworkDocument) {
        requirements = document.requirements.count
        byKind = Dictionary(grouping: document.requirements, by: \.kind).mapValues(\.count)
        var depthCounts: [Int] = []
        func walk(_ groups: [RequirementGroup], depth: Int) {
            guard !groups.isEmpty else { return }
            if depthCounts.count <= depth { depthCounts.append(0) }
            depthCounts[depth] += groups.count
            for g in groups { walk(g.groups, depth: depth + 1) }
        }
        walk(document.groups, depth: 0)
        groups = depthCounts
        withdrawn = document.withdrawn.count
        parameters = document.requirements.reduce(0) { $0 + $1.editableParameters.count }
        withEditorial = document.requirements.filter { $0.editorial != nil }.count
        if document.baselines.isEmpty {
            byBaseline = nil
        } else {
            var out: [String: [String: Int]] = [:]
            for b in document.baselines {
                let members = document.requirements.filter { $0.baselines.contains(b.id) }
                out[b.id] = Dictionary(grouping: members, by: \.kind).mapValues(\.count)
            }
            byBaseline = out
        }
    }

    /// Total items in a baseline across all kinds.
    public func total(inBaseline id: String) -> Int {
        byBaseline?[id]?.values.reduce(0, +) ?? 0
    }
}

public struct MappingIndexEntry: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let file: String
    public let fromFramework: String
    public let toFramework: String
    public let relationshipType: String
    public let entries: Int
    public let pairs: Int
}
