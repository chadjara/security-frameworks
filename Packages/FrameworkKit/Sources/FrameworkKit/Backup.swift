import CommonCrypto
import CryptoKit
import Foundation

// MARK: - Archive model

/// Everything in one or more assessments, independent of the app's storage layer.
public struct BackupArchive: Codable, Sendable, Equatable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var createdAt: Date
    public var appVersion: String
    public var assessments: [AssessmentRecord]

    public init(createdAt: Date = Date(), appVersion: String, assessments: [AssessmentRecord]) {
        self.formatVersion = Self.currentFormatVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.assessments = assessments
    }
}

public struct AssessmentRecord: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var organization: String
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date
    public var enabledFrameworkIDs: [String]
    public var scopes: [String: ScopeSelection]
    public var csfCurrentTier: Int?
    public var csfTargetTier: Int?
    public var responses: [ResponseRecord]
    public var parameterValues: [ParameterValueRecord]
    public var evidence: [EvidenceRecord]

    public init(id: UUID, name: String, organization: String, notes: String, createdAt: Date, updatedAt: Date,
                enabledFrameworkIDs: [String], scopes: [String: ScopeSelection], csfCurrentTier: Int?,
                csfTargetTier: Int?, responses: [ResponseRecord], parameterValues: [ParameterValueRecord],
                evidence: [EvidenceRecord]) {
        self.id = id
        self.name = name
        self.organization = organization
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.enabledFrameworkIDs = enabledFrameworkIDs
        self.scopes = scopes
        self.csfCurrentTier = csfCurrentTier
        self.csfTargetTier = csfTargetTier
        self.responses = responses
        self.parameterValues = parameterValues
        self.evidence = evidence
    }
}

public struct ResponseRecord: Codable, Sendable, Equatable {
    public var frameworkID: String
    public var requirementID: String
    public var status: RequirementStatus
    public var notApplicableReason: String
    public var owner: String
    public var targetDate: Date?
    public var notes: String
    public var targetStatusRaw: String?
    public var priorityRaw: String?
    public var appliedFromFrameworkID: String?
    public var appliedFromRequirementID: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var evidenceIDs: [UUID]

    public init(frameworkID: String, requirementID: String, status: RequirementStatus, notApplicableReason: String,
                owner: String, targetDate: Date?, notes: String, targetStatusRaw: String?, priorityRaw: String?,
                appliedFromFrameworkID: String?, appliedFromRequirementID: String?, createdAt: Date, updatedAt: Date,
                evidenceIDs: [UUID]) {
        self.frameworkID = frameworkID
        self.requirementID = requirementID
        self.status = status
        self.notApplicableReason = notApplicableReason
        self.owner = owner
        self.targetDate = targetDate
        self.notes = notes
        self.targetStatusRaw = targetStatusRaw
        self.priorityRaw = priorityRaw
        self.appliedFromFrameworkID = appliedFromFrameworkID
        self.appliedFromRequirementID = appliedFromRequirementID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.evidenceIDs = evidenceIDs
    }
}

public struct ParameterValueRecord: Codable, Sendable, Equatable {
    public var frameworkID: String
    public var parameterID: String
    public var value: String
    public var updatedAt: Date

    public init(frameworkID: String, parameterID: String, value: String, updatedAt: Date) {
        self.frameworkID = frameworkID
        self.parameterID = parameterID
        self.value = value
        self.updatedAt = updatedAt
    }
}

public struct EvidenceRecord: Codable, Sendable, Equatable {
    public var id: UUID
    public var kind: String
    public var title: String
    public var text: String
    public var urlString: String
    public var storedFileName: String?
    public var originalFileName: String?
    public var contentTypeIdentifier: String?
    public var byteCount: Int
    public var createdAt: Date

    public init(id: UUID, kind: String, title: String, text: String, urlString: String, storedFileName: String?,
                originalFileName: String?, contentTypeIdentifier: String?, byteCount: Int, createdAt: Date) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.urlString = urlString
        self.storedFileName = storedFileName
        self.originalFileName = originalFileName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}

/// An archive plus the evidence files it references, keyed by "<assessment UUID>/<stored file name>".
public struct BackupPayload: Sendable, Equatable {
    public var archive: BackupArchive
    public var files: [String: Data]

    public init(archive: BackupArchive, files: [String: Data]) {
        self.archive = archive
        self.files = files
    }

    public static func fileKey(assessmentID: UUID, storedFileName: String) -> String {
        "\(assessmentID.uuidString)/\(storedFileName)"
    }
}

// MARK: - Encrypted container

/// The `.fwbackup` file format.
///
///     "FWBK" (4 bytes) | version (1 byte) | PBKDF2 iterations (UInt32, big-endian) | salt (16 bytes)
///     | AES-256-GCM sealed box (12-byte nonce, ciphertext, 16-byte tag)
///
/// The key is derived from the user's password with PBKDF2-HMAC-SHA256. The header is authenticated as
/// additional data, so any change to it, the ciphertext, or a wrong password fails to open. The
/// plaintext is an LZFSE-compressed frame: a JSON manifest followed by the evidence files.
public enum BackupCodec {
    public static let magic: [UInt8] = Array("FWBK".utf8)
    public static let currentVersion: UInt8 = 1
    public static let defaultIterations: UInt32 = 600_000
    public static let minimumPasswordLength = 8
    static let saltLength = 16
    static let headerLength = 4 + 1 + 4 + 16

    public enum BackupError: Error, Equatable, LocalizedError {
        case passwordTooShort
        case notABackup
        case unsupportedVersion(UInt8)
        case wrongPasswordOrDamaged
        case damaged

        public var errorDescription: String? {
            switch self {
            case .passwordTooShort:
                return "Use a password of at least \(BackupCodec.minimumPasswordLength) characters."
            case .notABackup:
                return "This file is not a backup created by this app."
            case .unsupportedVersion:
                return "This backup was created by a newer version of the app. Update the app, then try again."
            case .wrongPasswordOrDamaged:
                return "The password is incorrect, or the backup file is damaged."
            case .damaged:
                return "The backup file is damaged and cannot be restored."
            }
        }
    }

    public static func encode(_ payload: BackupPayload, password: String,
                              iterations: UInt32 = defaultIterations) throws -> Data {
        guard password.count >= minimumPasswordLength else { throw BackupError.passwordTooShort }
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        var header = Data(magic)
        header.append(currentVersion)
        withUnsafeBytes(of: iterations.bigEndian) { header.append(contentsOf: $0) }
        header.append(salt)

        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let plain = try compress(pack(payload))
        let sealed = try AES.GCM.seal(plain, using: key, authenticating: header)
        guard let combined = sealed.combined else { throw BackupError.damaged }
        return header + combined
    }

    public static func decode(_ data: Data, password: String) throws -> BackupPayload {
        let bytes = [UInt8](data)
        guard bytes.count > headerLength, Array(bytes[0..<4]) == magic else { throw BackupError.notABackup }
        let version = bytes[4]
        guard version <= currentVersion else { throw BackupError.unsupportedVersion(version) }
        let iterations = bytes[5..<9].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard iterations > 0 else { throw BackupError.damaged }
        let salt = Data(bytes[9..<headerLength])
        let header = Data(bytes[0..<headerLength])
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let plain: Data
        do {
            let box = try AES.GCM.SealedBox(combined: Data(bytes[headerLength...]))
            plain = try AES.GCM.open(box, using: key, authenticating: header)
        } catch {
            throw BackupError.wrongPasswordOrDamaged
        }
        return try unpack(decompress(plain))
    }

    /// Reads the format version without the password (for messages like "made by a newer version").
    public static func isBackup(_ data: Data) -> Bool {
        data.count > headerLength && Array(data.prefix(4)) == magic
    }

    // MARK: Key derivation

    static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let normalized = password.precomposedStringWithCanonicalMapping
        var derived = [UInt8](repeating: 0, count: 32)
        let saltBytes = [UInt8](salt)
        let status = normalized.withCString { pw -> Int32 in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw, strlen(pw), saltBytes, saltBytes.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &derived, derived.count)
        }
        guard status == Int32(kCCSuccess) else { throw BackupError.damaged }
        return SymmetricKey(data: derived)
    }

    // MARK: Framing

    static func pack(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let manifest = try encoder.encode(payload.archive)
        var out = Data()
        appendUInt64(UInt64(manifest.count), to: &out)
        out.append(manifest)
        let names = payload.files.keys.sorted()
        appendUInt64(UInt64(names.count), to: &out)
        for name in names {
            let nameBytes = Data(name.utf8)
            let file = payload.files[name] ?? Data()
            appendUInt64(UInt64(nameBytes.count), to: &out)
            out.append(nameBytes)
            appendUInt64(UInt64(file.count), to: &out)
            out.append(file)
        }
        return out
    }

    static func unpack(_ data: Data) throws -> BackupPayload {
        var reader = ByteReader(bytes: [UInt8](data))
        let manifest = try reader.read(count: Int(try reader.readUInt64()))
        let archive: BackupArchive
        do {
            archive = try JSONDecoder().decode(BackupArchive.self, from: Data(manifest))
        } catch {
            throw BackupError.damaged
        }
        guard archive.formatVersion <= BackupArchive.currentFormatVersion else {
            throw BackupError.unsupportedVersion(UInt8(clamping: archive.formatVersion))
        }
        var files: [String: Data] = [:]
        let count = try reader.readUInt64()
        for _ in 0..<count {
            let name = try reader.read(count: Int(try reader.readUInt64()))
            let body = try reader.read(count: Int(try reader.readUInt64()))
            guard let key = String(bytes: name, encoding: .utf8) else { throw BackupError.damaged }
            files[key] = Data(body)
        }
        guard reader.isAtEnd else { throw BackupError.damaged }
        return BackupPayload(archive: archive, files: files)
    }

    static func appendUInt64(_ value: UInt64, to data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    static func compress(_ data: Data) throws -> Data {
        do { return try (data as NSData).compressed(using: .lzfse) as Data } catch { throw BackupError.damaged }
    }

    static func decompress(_ data: Data) throws -> Data {
        do { return try (data as NSData).decompressed(using: .lzfse) as Data } catch { throw BackupError.damaged }
    }
}

/// Bounds-checked sequential reader.
struct ByteReader {
    let bytes: [UInt8]
    var offset = 0

    var isAtEnd: Bool { offset == bytes.count }

    mutating func read(count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= bytes.count - offset else { throw BackupCodec.BackupError.damaged }
        defer { offset += count }
        return bytes[offset..<(offset + count)]
    }

    mutating func readUInt64() throws -> UInt64 {
        try read(count: 8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }
}
