import Foundation

/// A requirement in a specific framework. This is how user answers are keyed.
public struct RequirementRef: Sendable, Hashable, Codable, Comparable {
    public let frameworkID: String
    public let requirementID: String

    public init(frameworkID: String, requirementID: String) {
        self.frameworkID = frameworkID
        self.requirementID = requirementID
    }

    public static func < (a: RequirementRef, b: RequirementRef) -> Bool {
        (a.frameworkID, a.requirementID) < (b.frameworkID, b.requirementID)
    }
}

/// One NIST-published relationship from a requirement to a requirement in another framework.
public struct MappingLink: Sendable, Hashable {
    public enum Direction: Sendable, Hashable {
        /// The mapping file lists this requirement as `from`.
        case forward
        /// The mapping file lists this requirement as a target; shown as "referenced by".
        case reverse
    }

    public let target: RequirementRef
    public let relationship: RelationshipType
    public let mappingID: String
    public let direction: Direction
}

/// Bidirectional lookup over all mapping files. Nothing is inferred or chained: only pairs that
/// appear in a NIST-published mapping file are returned.
public struct MappingGraph: Sendable {
    public let documents: [MappingDocument]
    private let links: [RequirementRef: [MappingLink]]

    public init(documents: [MappingDocument]) {
        self.documents = documents
        var out: [RequirementRef: [MappingLink]] = [:]
        for doc in documents {
            for entry in doc.entries {
                let from = RequirementRef(frameworkID: doc.fromFramework, requirementID: entry.from)
                for to in entry.to {
                    let target = RequirementRef(frameworkID: doc.toFramework, requirementID: to)
                    out[from, default: []].append(MappingLink(target: target, relationship: doc.relationship.type,
                                                              mappingID: doc.id, direction: .forward))
                    out[target, default: []].append(MappingLink(target: from, relationship: doc.relationship.type,
                                                                mappingID: doc.id, direction: .reverse))
                }
            }
        }
        links = out
    }

    /// Links from `ref`, optionally limited to frameworks the assessment has enabled.
    public func links(from ref: RequirementRef, enabledFrameworks: Set<String>? = nil) -> [MappingLink] {
        let all = links[ref] ?? []
        guard let enabled = enabledFrameworks else { return all }
        return all.filter { enabled.contains($0.target.frameworkID) }
    }

    public func document(_ id: String) -> MappingDocument? { documents.first { $0.id == id } }

    public var pairCount: Int { documents.reduce(0) { $0 + $1.entries.reduce(0) { $0 + $1.to.count } } }
}
