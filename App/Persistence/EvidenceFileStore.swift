import Foundation
import UniformTypeIdentifiers

/// Stores evidence files on disk, one folder per assessment, with complete file protection.
enum EvidenceFileStore {
    struct StoredFile: Equatable {
        let storedFileName: String
        let originalFileName: String
        let contentType: UTType?
        let byteCount: Int
    }

    enum StoreError: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "\(name) could not be read. Check that the file is available on this device and try again."
            }
        }
    }

    /// Root folder for evidence. Tests can point this at a temporary directory.
    nonisolated(unsafe) static var rootOverride: URL?

    static func directory(for assessmentID: UUID) throws -> URL {
        let root = try rootOverride ?? AppDirectories.evidenceDirectory()
        let dir = root.appendingPathComponent(assessmentID.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
        }
        return dir
    }

    static func url(forStoredFile name: String, assessmentID: UUID) -> URL? {
        try? directory(for: assessmentID).appendingPathComponent(name)
    }

    /// Copies a file the user picked (Files, drag and drop) into the assessment's folder.
    static func importFile(at source: URL, assessmentID: UUID) throws -> StoredFile {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension
        let name = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let dest = try directory(for: assessmentID).appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
        } catch {
            throw StoreError.unreadable(source.lastPathComponent)
        }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: dest.path)
        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
        return StoredFile(storedFileName: name, originalFileName: source.lastPathComponent,
                          contentType: UTType(filenameExtension: ext), byteCount: size)
    }

    /// Writes data (for example a photo) into the assessment's folder.
    static func save(_ data: Data, fileExtension: String, originalFileName: String, assessmentID: UUID) throws -> StoredFile {
        let name = UUID().uuidString + ".\(fileExtension)"
        let dest = try directory(for: assessmentID).appendingPathComponent(name)
        try data.write(to: dest, options: [.atomic, .completeFileProtection])
        return StoredFile(storedFileName: name, originalFileName: originalFileName,
                          contentType: UTType(filenameExtension: fileExtension), byteCount: data.count)
    }

    static func delete(storedFileName name: String, assessmentID: UUID) {
        guard let url = url(forStoredFile: name, assessmentID: assessmentID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll(for assessmentID: UUID) {
        guard let dir = try? directory(for: assessmentID) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Copies every stored file from one assessment to another (used when duplicating).
    static func copyFile(named name: String, from source: UUID, to destination: UUID) throws {
        guard let from = url(forStoredFile: name, assessmentID: source) else { return }
        let to = try directory(for: destination).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: from.path) {
            try FileManager.default.copyItem(at: from, to: to)
        }
    }
}
