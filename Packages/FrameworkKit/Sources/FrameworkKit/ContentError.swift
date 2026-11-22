import Foundation

public enum ContentError: Error, Sendable, Equatable, LocalizedError {
    case contentDirectoryMissing(String)
    case fileMissing(String)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case decodingFailed(file: String, reason: String)
    case unknownFramework(String)
    case validationFailed([String])

    public var errorDescription: String? {
        switch self {
        case .contentDirectoryMissing(let path):
            return "Framework content was not found at \(path)."
        case .fileMissing(let file):
            return "The content file \(file) is missing."
        case .unsupportedSchemaVersion(let found, let supported):
            return "This content uses schema version \(found), but this version of the app supports up to \(supported). Update the app to use it."
        case .decodingFailed(let file, let reason):
            return "The content file \(file) could not be read: \(reason)"
        case .unknownFramework(let id):
            return "No framework with the identifier \(id) is installed."
        case .validationFailed(let issues):
            return "Framework content failed validation (\(issues.count) issue\(issues.count == 1 ? "" : "s"))."
        }
    }
}
