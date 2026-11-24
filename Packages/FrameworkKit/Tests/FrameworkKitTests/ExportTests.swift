import Foundation
import Testing
@testable import FrameworkKit

@Suite("CSV")
struct CSVTests {
    @Test("Fields are quoted only when needed, and quotes are doubled")
    func quoting() {
        #expect(CSV.field("plain") == "plain")
        #expect(CSV.field("a,b") == "\"a,b\"")
        #expect(CSV.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSV.field("line1\nline2") == "\"line1\nline2\"")
        #expect(CSV.field(" padded ") == "\" padded \"")
        #expect(CSV.field("") == "")
    }

    @Test("Values a spreadsheet would run as formulas are neutralized")
    func formulaInjection() {
        #expect(CSV.field("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(CSV.field("+1") == "'+1")
        #expect(CSV.field("@SUM(A1)") == "'@SUM(A1)")
        #expect(CSV.field("-2+3") == "'-2+3")
        #expect(CSV.field("- a bullet") == "- a bullet")
        #expect(CSV.field("AC-2(1)") == "AC-2(1)")
    }

    @Test("Documents use CRLF and a UTF-8 byte-order mark")
    func document() {
        let data = CSV.data(header: ["ID", "Title"], rows: [["GV.OC-01", "Mission, understood"]])
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        #expect(text == "ID,Title\r\nGV.OC-01,\"Mission, understood\"\r\n")
    }
}

@Suite("Encrypted backup")
struct BackupTests {
    static let iterations: UInt32 = 1_000 // Fast for tests; the app uses BackupCodec.defaultIterations.

    static func samplePayload() -> BackupPayload {
        let assessmentID = UUID()
        let evidenceID = UUID()
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000.25)
        let record = AssessmentRecord(
            id: assessmentID, name: "Harbor Clinic 2026", organization: "Harbor Family Clinic", notes: "Línea, \"quoted\"",
            createdAt: date, updatedAt: date, enabledFrameworkIDs: ["csf-2.0", "sp800-53r5"],
            scopes: ["sp800-53r5": ScopeSelection(baselineID: "moderate", additiveBaselineIDs: ["privacy"], addedRequirementIDs: ["ac-2.13"])],
            csfCurrentTier: 2, csfTargetTier: 3,
            responses: [ResponseRecord(frameworkID: "csf-2.0", requirementID: "GV.OC-01", status: .notApplicable,
                                       notApplicableReason: "No reason needed", owner: "IT", targetDate: date, notes: "n",
                                       targetStatusRaw: "excluded", priorityRaw: "high", appliedFromFrameworkID: nil,
                                       appliedFromRequirementID: nil, createdAt: date, updatedAt: date, evidenceIDs: [evidenceID])],
            parameterValues: [ParameterValueRecord(frameworkID: "sp800-171r3", parameterID: "A.03.01.01.ODP.01", value: "90 days", updatedAt: date)],
            evidence: [EvidenceRecord(id: evidenceID, kind: "file", title: "Scan", text: "", urlString: "",
                                      storedFileName: "abc.pdf", originalFileName: "scan.pdf",
                                      contentTypeIdentifier: "com.adobe.pdf", byteCount: 4, createdAt: date)]
        )
        let archive = BackupArchive(createdAt: date, appVersion: "0.1.0 (104)", assessments: [record])
        let files = [BackupPayload.fileKey(assessmentID: assessmentID, storedFileName: "abc.pdf"): Data([0x25, 0x50, 0x44, 0x46])]
        return BackupPayload(archive: archive, files: files)
    }

    @Test("Round trip restores every field and file exactly")
    func roundTrip() throws {
        let payload = Self.samplePayload()
        let data = try BackupCodec.encode(payload, password: "correct horse battery", iterations: Self.iterations)
        #expect(BackupCodec.isBackup(data))
        #expect(Array(data.prefix(4)) == Array("FWBK".utf8))
        let restored = try BackupCodec.decode(data, password: "correct horse battery")
        #expect(restored == payload)
    }

    @Test("The plaintext never appears in the file")
    func encrypted() throws {
        let data = try BackupCodec.encode(Self.samplePayload(), password: "correct horse battery", iterations: Self.iterations)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("Harbor"))
        #expect(!text.contains("90 days"))
    }

    @Test("A wrong password fails without revealing anything")
    func wrongPassword() throws {
        let data = try BackupCodec.encode(Self.samplePayload(), password: "correct horse battery", iterations: Self.iterations)
        #expect(throws: BackupCodec.BackupError.wrongPasswordOrDamaged) {
            _ = try BackupCodec.decode(data, password: "wrong horse battery")
        }
    }

    @Test("Any change to the header or ciphertext is detected")
    func tampering() throws {
        let data = try BackupCodec.encode(Self.samplePayload(), password: "correct horse battery", iterations: Self.iterations)
        var flippedCipher = data
        flippedCipher[flippedCipher.count - 20] ^= 0x01
        #expect(throws: BackupCodec.BackupError.wrongPasswordOrDamaged) {
            _ = try BackupCodec.decode(flippedCipher, password: "correct horse battery")
        }
        var flippedSalt = data
        flippedSalt[12] ^= 0x01
        #expect(throws: BackupCodec.BackupError.wrongPasswordOrDamaged) {
            _ = try BackupCodec.decode(flippedSalt, password: "correct horse battery")
        }
    }

    @Test("Short passwords, other files, and newer versions are rejected clearly")
    func validation() throws {
        #expect(throws: BackupCodec.BackupError.passwordTooShort) {
            _ = try BackupCodec.encode(Self.samplePayload(), password: "short", iterations: Self.iterations)
        }
        #expect(throws: BackupCodec.BackupError.notABackup) {
            _ = try BackupCodec.decode(Data("not a backup at all, just text".utf8), password: "whatever123")
        }
        var future = try BackupCodec.encode(Self.samplePayload(), password: "correct horse battery", iterations: Self.iterations)
        future[4] = 99
        #expect(throws: BackupCodec.BackupError.unsupportedVersion(99)) {
            _ = try BackupCodec.decode(future, password: "correct horse battery")
        }
    }

    @Test("Passwords are compared after Unicode normalization")
    func normalization() throws {
        let composed = "caf\u{00E9}-password"
        let decomposed = "cafe\u{0301}-password"
        let data = try BackupCodec.encode(Self.samplePayload(), password: composed, iterations: Self.iterations)
        #expect(throws: Never.self) { _ = try BackupCodec.decode(data, password: decomposed) }
    }

    @Test("Truncated frames are reported as damaged, not crashes")
    func truncatedFrame() {
        #expect(throws: BackupCodec.BackupError.damaged) {
            _ = try BackupCodec.unpack(Data([0, 0, 0, 0, 0, 0, 0, 10, 1, 2]))
        }
    }
}
