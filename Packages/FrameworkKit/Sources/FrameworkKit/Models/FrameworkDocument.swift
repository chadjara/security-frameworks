import Foundation

/// A framework content file (`*.framework.json`), schema version 1. See docs/SCHEMA.md.
public struct FrameworkDocument: Sendable, Hashable, Codable, Identifiable {
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let id: String
    public let shortName: String
    public let title: String
    public let publisher: String
    public let publicationId: String
    public let version: String
    public let contentVersion: String
    public let source: SourceInfo
    public let summary: FrameworkSummary?
    public let notices: [Notice]
    public let kinds: [RequirementKind]
    public let groupLevels: [GroupLevel]
    public let baselines: [Baseline]
    /// CSF 2.0 Tiers (empty for other frameworks).
    public let tiers: [Tier]
    public let tiersSource: TiersSource?
    public let groups: [RequirementGroup]
    public let requirements: [Requirement]
    public let withdrawn: [WithdrawnRequirement]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, shortName, title, publisher, publicationId, version, contentVersion, source
        case summary, notices, kinds, groupLevels, baselines, tiers, tiersSource, groups, requirements, withdrawn
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion <= Self.supportedSchemaVersion else {
            throw ContentError.unsupportedSchemaVersion(found: schemaVersion, supported: Self.supportedSchemaVersion)
        }
        id = try c.decode(String.self, forKey: .id)
        shortName = try c.decode(String.self, forKey: .shortName)
        title = try c.decode(String.self, forKey: .title)
        publisher = try c.decode(String.self, forKey: .publisher)
        publicationId = try c.decode(String.self, forKey: .publicationId)
        version = try c.decode(String.self, forKey: .version)
        contentVersion = try c.decode(String.self, forKey: .contentVersion)
        source = try c.decode(SourceInfo.self, forKey: .source)
        summary = try c.decodeIfPresent(FrameworkSummary.self, forKey: .summary)
        notices = try c.decodeIfPresent([Notice].self, forKey: .notices) ?? []
        kinds = try c.decode([RequirementKind].self, forKey: .kinds)
        groupLevels = try c.decode([GroupLevel].self, forKey: .groupLevels)
        baselines = try c.decodeIfPresent([Baseline].self, forKey: .baselines) ?? []
        tiers = try c.decodeIfPresent([Tier].self, forKey: .tiers) ?? []
        tiersSource = try c.decodeIfPresent(TiersSource.self, forKey: .tiersSource)
        groups = try c.decode([RequirementGroup].self, forKey: .groups)
        requirements = try c.decode([Requirement].self, forKey: .requirements)
        withdrawn = try c.decodeIfPresent([WithdrawnRequirement].self, forKey: .withdrawn) ?? []
    }
}

public struct SourceInfo: Sendable, Hashable, Codable {
    public let oscalUrl: String
    public let oscalBrowseUrl: String?
    public let oscalCommit: String?
    public let catalogTitle: String?
    public let catalogVersion: String?
    public let oscalVersion: String?
    public let lastModified: String?
    public let sha256: String
    public let retrieved: String
    public let publicationUrl: String?
    public let baselinesPublicationUrl: String?
    public let referenceToolUrl: String?
}

public struct FrameworkSummary: Sendable, Hashable, Codable {
    public let plainDescription: String
    public let audience: String
    public let covers: String
    public let typicalEffort: String
    public let whenToChoose: String
}

public struct Notice: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
}

public struct RequirementKind: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let singular: String
    public let plural: String
}

public struct GroupLevel: Sendable, Hashable, Codable {
    public let singular: String
    public let plural: String
}

public struct Baseline: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let title: String
    /// `true` when the baseline is layered on top of another one (the SP 800-53B Privacy baseline).
    public let additive: Bool
    public let summary: String?
}

/// A CSF Tier: the rigor of cybersecurity risk governance and management practices (NIST text).
public struct Tier: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let number: Int
    public let title: String
    public let governance: [String]
    public let management: [String]
}

public struct TiersSource: Sendable, Hashable, Codable {
    public let url: String
    public let pages: String
    public let sha256: String
    public let introduction: String?
}

public struct RequirementGroup: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let displayId: String
    public let title: String
    public let description: String?
    public let groups: [RequirementGroup]
    /// Top-level requirements only. Children (SP 800-53 enhancements) are found through `parentId`.
    public let requirementIds: [String]

    enum CodingKeys: String, CodingKey { case id, displayId, title, description, groups, requirementIds }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayId = try c.decode(String.self, forKey: .displayId)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        groups = try c.decodeIfPresent([RequirementGroup].self, forKey: .groups) ?? []
        requirementIds = try c.decodeIfPresent([String].self, forKey: .requirementIds) ?? []
    }

    public var isLeaf: Bool { groups.isEmpty }
}

public struct WithdrawnRequirement: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let displayId: String
    public let title: String?
    public let incorporatedInto: [String]
    public let movedTo: [String]
    public let addressedBy: [String]

    enum CodingKeys: String, CodingKey { case id, displayId, title, incorporatedInto, movedTo, addressedBy }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayId = try c.decode(String.self, forKey: .displayId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        incorporatedInto = try c.decodeIfPresent([String].self, forKey: .incorporatedInto) ?? []
        movedTo = try c.decodeIfPresent([String].self, forKey: .movedTo) ?? []
        addressedBy = try c.decodeIfPresent([String].self, forKey: .addressedBy) ?? []
    }
}
