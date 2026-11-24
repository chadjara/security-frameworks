import FrameworkKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Encrypted assessment backups (declared in Info.plist).
    static let fwBackup = UTType(exportedAs: "com.cjaratech.securityframework.backup", conformingTo: .data)
}

/// Report, spreadsheet, and encrypted backup for one assessment.
struct ExportSheet: View {
    private struct Ready: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
        let detail: String
    }

    @Bindable var assessment: Assessment
    @Environment(ContentLibrary.self) private var library
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var reportScope = "all"
    @State private var includeDetails = true
    @State private var password = ""
    @State private var confirmation = ""
    @State private var working: String?
    @State private var ready: Ready?
    @State private var errorMessage: String?

    private var enabledFrameworks: [Framework] { assessment.enabledFrameworkIDs.compactMap(library.framework) }
    private var passwordProblem: String? {
        if password.isEmpty { return nil }
        if password.count < BackupCodec.minimumPasswordLength {
            return "Use at least \(BackupCodec.minimumPasswordLength) characters."
        }
        if !confirmation.isEmpty && confirmation != password { return "The passwords do not match." }
        return nil
    }
    private var canBackUp: Bool {
        password.count >= BackupCodec.minimumPasswordLength && password == confirmation
    }

    var body: some View {
        NavigationStack {
            Form {
                if let ready {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ready.title).font(.dsHeadline)
                                Text(ready.detail).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.dsImplemented)
                        }
                        ShareLink(item: ready.url) {
                            Label("Share or Save to Files", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("shareExport")
                    } footer: {
                        Text("Choose Save to Files to keep a copy, or send it with AirDrop, Mail, or another app. The app does not keep exported copies.")
                            .font(.dsFootnote)
                    }
                }

                Section {
                    Picker("Frameworks", selection: $reportScope) {
                        if enabledFrameworks.count > 1 && entitlements.isUnlocked(.combinedReports) {
                            Text("All turned-on frameworks").tag("all")
                        }
                        ForEach(enabledFrameworks) { fw in Text(fw.document.shortName).tag(fw.id) }
                    }
                    Toggle("Include requirement details", isOn: $includeDetails)
                    actionButton("Create PDF Report", systemImage: "doc.richtext", key: "pdf", disabled: enabledFrameworks.isEmpty) {
                        try makeReport()
                    }
                } header: {
                    SectionHeader("Report (PDF)")
                } footer: {
                    Text("A printable summary with progress, next steps, and, if included, every requirement in scope with its status, owner, notes, and evidence list.")
                        .font(.dsFootnote)
                }

                Section {
                    actionButton("Create Spreadsheet", systemImage: "tablecells", key: "csv", disabled: enabledFrameworks.isEmpty) {
                        try makeCSV()
                    }
                } header: {
                    SectionHeader("Spreadsheet (CSV)")
                } footer: {
                    Text("One row per requirement in every turned-on framework, with status, owner, dates, notes, and organization-defined values.")
                        .font(.dsFootnote)
                }

                Section {
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("backupPassword")
                    SecureField("Confirm password", text: $confirmation)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("backupConfirm")
                    if let passwordProblem {
                        Text(passwordProblem).font(.dsFootnote).foregroundStyle(Color.dsDestructive)
                    }
                    actionButton("Create Encrypted Backup", systemImage: "lock.doc", key: "backup", disabled: !canBackUp) {
                        let url = try await BackupService(context: context).makeBackup(of: [assessment], password: password)
                        password = ""
                        confirmation = ""
                        return Ready(url: url, title: "Backup ready", detail: url.lastPathComponent)
                    }
                } header: {
                    SectionHeader("Encrypted backup")
                } footer: {
                    Text("Includes every answer, note, and evidence file, encrypted with AES-256 using a key derived from your password. Store the password somewhere safe: without it, the backup cannot be opened by anyone, including us.")
                        .font(.dsFootnote)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.dsCallout)
                            .foregroundStyle(Color.dsDestructive)
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if reportScope == "all" && !(enabledFrameworks.count > 1 && entitlements.isUnlocked(.combinedReports)) {
                    reportScope = enabledFrameworks.first?.id ?? "all"
                }
            }
            .accessibilityIdentifier("screen.export")
        }
    }

    private func actionButton(_ title: String, systemImage: String, key: String, disabled: Bool,
                              action: @escaping () async throws -> Ready) -> some View {
        Button {
            working = key
            errorMessage = nil
            Task {
                do {
                    ready = try await action()
                } catch {
                    errorMessage = error.localizedDescription
                }
                working = nil
            }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if working == key { ProgressView() }
            }
        }
        .disabled(disabled || working != nil)
        .accessibilityIdentifier("export.\(key)")
    }

    private func reportFrameworks() -> [Framework] {
        reportScope == "all" ? enabledFrameworks : enabledFrameworks.filter { $0.id == reportScope }
    }

    private func makeReport() throws -> Ready {
        let fws = reportFrameworks()
        let url = try PDFReport(assessment: assessment, frameworks: fws, graph: library.mappingGraph,
                                includeDetails: includeDetails).render()
        return Ready(url: url, title: "Report ready", detail: url.lastPathComponent)
    }

    private func makeCSV() throws -> Ready {
        let url = try ReportBuilder(assessment: assessment, frameworks: enabledFrameworks).csvFile()
        return Ready(url: url, title: "Spreadsheet ready", detail: url.lastPathComponent)
    }
}

/// Opens an encrypted backup and restores its assessments as new assessments.
struct RestoreBackupView: View {
    let fileURL: URL
    var onRestored: ((String) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var working = false
    @State private var errorMessage: String?
    @State private var payload: BackupPayload?
    @State private var restoredNames: [String]?

    var body: some View {
        NavigationStack {
            Form {
                if let restoredNames {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Restored").font(.dsHeadline)
                                Text(restoredNames.joined(separator: ", ")).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.dsImplemented)
                        }
                    } footer: {
                        Text("Restored assessments were added alongside your existing ones. Nothing was overwritten.").font(.dsFootnote)
                    }
                } else if let payload {
                    Section {
                        ForEach(payload.archive.assessments, id: \.id) { a in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).font(.dsHeadline)
                                Text("\(a.responses.count) answers · \(a.evidence.count) evidence items").font(.dsFootnote)
                                    .foregroundStyle(Color.dsTextSecondary)
                            }
                        }
                        Button {
                            restore(payload)
                        } label: {
                            Label("Restore \(payload.archive.assessments.count == 1 ? "Assessment" : "Assessments")", systemImage: "arrow.down.doc")
                        }
                        .disabled(working)
                    } header: {
                        SectionHeader("In this backup")
                    } footer: {
                        Text("Created \(payload.archive.createdAt.formatted(date: .abbreviated, time: .shortened)) with version \(payload.archive.appVersion).")
                            .font(.dsFootnote)
                    }
                } else {
                    Section {
                        Text(fileURL.lastPathComponent).font(.dsBody)
                        SecureField("Backup password", text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit(open)
                            .accessibilityIdentifier("restorePassword")
                        Button {
                            open()
                        } label: {
                            HStack {
                                Label("Open Backup", systemImage: "lock.open")
                                Spacer()
                                if working { ProgressView() }
                            }
                        }
                        .disabled(password.isEmpty || working)
                    } footer: {
                        Text("Enter the password chosen when the backup was created.").font(.dsFootnote)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.dsCallout)
                            .foregroundStyle(Color.dsDestructive)
                    }
                }
            }
            .navigationTitle("Restore Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(restoredNames == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    private func open() {
        guard !password.isEmpty else { return }
        working = true
        errorMessage = nil
        Task {
            do {
                let accessing = fileURL.startAccessingSecurityScopedResource()
                defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: fileURL)
                guard BackupCodec.isBackup(data) else { throw BackupCodec.BackupError.notABackup }
                payload = try await BackupService(context: context).decode(data, password: password)
                password = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            working = false
        }
    }

    private func restore(_ payload: BackupPayload) {
        working = true
        do {
            let summary = try BackupService(context: context).restore(payload)
            restoredNames = summary.assessmentNames
            if let first = summary.assessmentNames.first { onRestored?(first) }
        } catch {
            errorMessage = error.localizedDescription
        }
        working = false
    }
}

/// Restore entry point used from Settings: picks a file, then shows `RestoreBackupView`.
struct RestoreBackupButton: View {
    @State private var showingImporter = false
    @State private var selectedFile: URL?

    var body: some View {
        Button {
            showingImporter = true
        } label: {
            Label("Restore from Backup", systemImage: "arrow.down.doc")
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.fwBackup, .data]) { result in
            if case .success(let url) = result { selectedFile = url }
        }
        .sheet(item: $selectedFile) { url in RestoreBackupView(fileURL: url) }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
