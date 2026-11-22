import Foundation

/// A NIST-published mapping file (`*.mapping.json`).
public struct MappingDocument: Sendable, Hashable, Codable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let title: String
    public let fromFramework: String
    public let toFramework: String
    public let contentVersion: String
    public let relationship: Relationship
    public let source: MappingSource
    public let entries: [MappingEntry]

    public struct Relationship: Sendable, Hashable, Codable {
        public let type: RelationshipType
        public let description: String
    }

    public struct MappingSource: Sendable, Hashable, Codable {
        public let publisher: String
        public let description: String?
        public let url: String
        public let browseUrl: String?
        public let retrieved: String?
    }

    public struct MappingEntry: Sendable, Hashable, Codable {
        public let from: String
        public let to: [String]
    }
}

/// Open set of relationship types so newer content files still decode.
public struct RelationshipType: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// SP 800-171 requirement → the SP 800-53 control it was derived from.
    public static let sourceControl = RelationshipType(rawValue: "source-control")
    /// CSF 2.0 subcategory → a NIST informative reference that helps achieve it.
    public static let informativeReference = RelationshipType(rawValue: "informative-reference")

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}
