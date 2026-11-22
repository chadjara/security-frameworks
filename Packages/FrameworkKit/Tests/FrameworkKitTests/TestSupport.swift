import Foundation
@testable import FrameworkKit

enum TestContent {
    /// App/Resources/Content in the repository, located relative to this file.
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // FrameworkKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // FrameworkKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("App/Resources/Content")

    static let store = FrameworkStore(contentDirectory: directory)

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    /// A minimal, valid two-level framework used by unit tests.
    static let miniFrameworkJSON = """
    {
      "schemaVersion": 1, "id": "mini", "shortName": "Mini", "title": "Mini Framework", "publisher": "Test",
      "publicationId": "TEST 1", "version": "1", "contentVersion": "2026.11.0",
      "source": {"oscalUrl": "https://example.test/x.json", "sha256": "\(String(repeating: "0", count: 64))", "retrieved": "2026-11-22"},
      "kinds": [{"id": "control", "singular": "Control", "plural": "Controls"},
                {"id": "enhancement", "singular": "Enhancement", "plural": "Enhancements"}],
      "groupLevels": [{"singular": "Family", "plural": "Families"}],
      "baselines": [{"id": "low", "title": "Low", "additive": false}, {"id": "privacy", "title": "Privacy", "additive": true}],
      "groups": [{"id": "ac", "displayId": "AC", "title": "Access Control", "requirementIds": ["ac-1", "ac-2"]}],
      "requirements": [
        {"id": "ac-1", "displayId": "AC-1", "kind": "control", "title": "Policy and Procedures", "groupId": "ac",
         "sortKey": "ac-01", "statement": [{"text": "Disseminate to {{param:ac-1_prm_1}}."}],
         "parameters": [{"id": "ac-1_prm_1", "label": "personnel or roles", "aggregates": ["ac-01_odp.01", "ac-01_odp.02"]},
                        {"id": "ac-01_odp.01", "label": "personnel or roles"},
                        {"id": "ac-01_odp.02", "label": "personnel or roles"}],
         "baselines": ["low", "privacy"], "sourceUrl": "https://csrc.nist.gov/x"},
        {"id": "ac-2", "displayId": "AC-2", "kind": "control", "title": "Account Management", "groupId": "ac",
         "sortKey": "ac-02", "statement": [{"label": "a.", "text": "Disable accounts after {{param:ac-02_odp}}."}],
         "parameters": [{"id": "ac-02_odp", "label": "time period", "altId": "ac-2_prm_1"}],
         "baselines": ["low"], "sourceUrl": "https://csrc.nist.gov/x"},
        {"id": "ac-2.1", "displayId": "AC-2(1)", "kind": "enhancement", "title": "Automated Account Management",
         "groupId": "ac", "parentId": "ac-2", "sortKey": "ac-02.01",
         "statement": [{"text": "Support account management within {{param:ac-2_prm_1}}."}],
         "sourceUrl": "https://csrc.nist.gov/x"}
      ]
    }
    """
}
