import Foundation

/// One requirement: a CSF subcategory, an SP 800-53 control or enhancement, or an SP 800-171
/// security requirement. Every question in the app maps to exactly one requirement.
public struct Requirement: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let displayId: String
    public let kind: String
    public let title: String
    public let groupId: String
    public let parentId: String?
    public let sortKey: String
    public let statement: [TextItem]
    public let discussion: String?
    public let examples: [TextItem]
    public let objectives: [TextItem]
    public let parameters: [Parameter]
    public let baselines: [String]
    public let implementationLevels: [String]
    public let related: [String]
    public let references: [Reference]
    public let sourceUrl: String
    public let editorial: Editorial?

    enum CodingKeys: String, CodingKey {
        case id, displayId, kind, title, groupId, parentId, sortKey, statement, discussion, examples, objectives
        case parameters, baselines, implementationLevels, related, references, sourceUrl, editorial
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayId = try c.decode(String.self, forKey: .displayId)
        kind = try c.decode(String.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        groupId = try c.decode(String.self, forKey: .groupId)
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        sortKey = try c.decode(String.self, forKey: .sortKey)
        statement = try c.decode([TextItem].self, forKey: .statement)
        discussion = try c.decodeIfPresent(String.self, forKey: .discussion)
        examples = try c.decodeIfPresent([TextItem].self, forKey: .examples) ?? []
        objectives = try c.decodeIfPresent([TextItem].self, forKey: .objectives) ?? []
        parameters = try c.decodeIfPresent([Parameter].self, forKey: .parameters) ?? []
        baselines = try c.decodeIfPresent([String].self, forKey: .baselines) ?? []
        implementationLevels = try c.decodeIfPresent([String].self, forKey: .implementationLevels) ?? []
        related = try c.decodeIfPresent([String].self, forKey: .related) ?? []
        references = try c.decodeIfPresent([Reference].self, forKey: .references) ?? []
        sourceUrl = try c.decode(String.self, forKey: .sourceUrl)
        editorial = try c.decodeIfPresent(Editorial.self, forKey: .editorial)
    }

    /// Parameters the user fills in (aggregates are display-only roll-ups of other parameters).
    public var editableParameters: [Parameter] { parameters.filter { !$0.isAggregate } }

    public var isTopLevel: Bool { parentId == nil }
}

/// A node of statement, example, or assessment-objective text.
public struct TextItem: Sendable, Hashable, Codable {
    public let label: String?
    public let text: String?
    public let items: [TextItem]

    enum CodingKeys: String, CodingKey { case label, text, items }

    public init(label: String? = nil, text: String? = nil, items: [TextItem] = []) {
        self.label = label
        self.text = text
        self.items = items
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        items = try c.decodeIfPresent([TextItem].self, forKey: .items) ?? []
    }

    /// Depth-first list of this item and all descendants.
    public var flattened: [TextItem] { [self] + items.flatMap(\.flattened) }
}

public enum SelectionCount: String, Sendable, Hashable, Codable {
    case one
    case oneOrMore = "one-or-more"
}

/// An organization-defined parameter (ODP).
public struct Parameter: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let displayLabel: String?
    public let label: String?
    public let usage: String?
    public let guidance: String?
    public let choices: [String]
    public let howMany: SelectionCount?
    public let aggregates: [String]
    public let altId: String?

    enum CodingKeys: String, CodingKey { case id, displayLabel, label, usage, guidance, choices, howMany, aggregates, altId }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayLabel = try c.decodeIfPresent(String.self, forKey: .displayLabel)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        usage = try c.decodeIfPresent(String.self, forKey: .usage)
        guidance = try c.decodeIfPresent(String.self, forKey: .guidance)
        choices = try c.decodeIfPresent([String].self, forKey: .choices) ?? []
        howMany = try c.decodeIfPresent(SelectionCount.self, forKey: .howMany)
        aggregates = try c.decodeIfPresent([String].self, forKey: .aggregates) ?? []
        altId = try c.decodeIfPresent(String.self, forKey: .altId)
    }

    public var isSelection: Bool { !choices.isEmpty }
    public var isAggregate: Bool { !aggregates.isEmpty }
    public var allowsMultipleSelection: Bool { howMany == .oneOrMore }

    /// Short human-readable name for the value, e.g. "time period".
    public var placeholder: String {
        if let label, !label.isEmpty { return label }
        if let usage, !usage.isEmpty { return usage }
        return isSelection ? "selection" : "value"
    }
}

public struct Reference: Sendable, Hashable, Codable {
    public let title: String
    public let url: String?
}

/// Plain-language content written for this app (not NIST text).
public struct Editorial: Sendable, Hashable, Codable {
    public let question: String
    public let whyItMatters: String
    public let doneLooksLike: String
    public let nextSteps: [String]
    public let reviewed: Bool
}
