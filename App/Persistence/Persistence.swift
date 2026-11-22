import Foundation
import SwiftData

/// Where the app keeps user data. Everything lives under Application Support with
/// `FileProtectionType.complete` (also enforced app-wide by the Data Protection entitlement).
enum AppDirectories {
    static let excludeFromBackupKey = "excludeFromDeviceBackup"

    static func applicationSupport() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    /// Application Support/Data: the SwiftData store.
    static func dataDirectory() throws -> URL { try protectedDirectory(named: "Data") }

    /// Application Support/Evidence: evidence files, one folder per assessment.
    static func evidenceDirectory() throws -> URL { try protectedDirectory(named: "Evidence") }

    private static func protectedDirectory(named name: String) throws -> URL {
        let url = try applicationSupport().appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
        }
        return url
    }

    /// Applies complete file protection to a directory and everything in it.
    static func protectContents(of directory: URL) {
        let fm = FileManager.default
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        guard let items = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in items {
            try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        }
    }

    /// Whether user data is left out of iCloud and computer backups of the device. On by default so
    /// assessment data stays on the device; the encrypted export is the supported backup path.
    static var excludesFromBackup: Bool {
        UserDefaults.standard.object(forKey: excludeFromBackupKey) as? Bool ?? true
    }

    static func applyBackupExclusion() {
        let excluded = excludesFromBackup
        for dir in [try? dataDirectory(), try? evidenceDirectory()].compactMap({ $0 }) {
            var url = dir
            var values = URLResourceValues()
            values.isExcludedFromBackup = excluded
            try? url.setResourceValues(values)
        }
    }
}

enum Persistence {
    static var schema: Schema { Schema([Assessment.self, RequirementResponse.self, EvidenceItem.self, ParameterValue.self]) }

    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        let dir = try AppDirectories.dataDirectory()
        let config = ModelConfiguration(schema: schema, url: dir.appendingPathComponent("Assessments.store"))
        let container = try ModelContainer(for: schema, configurations: config)
        AppDirectories.protectContents(of: dir)
        AppDirectories.applyBackupExclusion()
        return container
    }
}
