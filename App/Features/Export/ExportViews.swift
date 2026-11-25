import FrameworkKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Encrypted assessment backups (declared in Info.plist).
    static let fwBackup = UTType(exportedAs: "com.cjaratech.securityframework.backup", conformingTo: .data)
}

/// Report, spreadsheet, data file, and encrypted backup for one assessment. The user picks a format,
/// the frameworks and requirements to include, and which kinds of information to leave out.
struct ExportSheet: View {
    private struct Ready: Identifiable {
        let id = UUID()
        let key: String
        let url: URL
        let title: String
        let detail: String
    }

    @Bindable var assessment: Assessment
    @Environment(ContentLibrary.self) private var library
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage("export.options") private var storedOptions = Data()
    @State private var options = ExportOptions()
    @State private var selectedFrameworkIDs: Set<String> = []
    @State private var password = ""
    @State private var confirmation = ""
    @State private var working: String?
    @State private var ready: Ready?
    @State private var errorMessage: String?

    private var enabledFrameworks: [Framework] { assessment.enabledFrameworkIDs.compactMap(library.framework) }
    private var canCombine: Bool { enabledFrameworks.count > 1 && entitlements.isUnlocked(.combinedReports) }
    private var selectedFrameworks: [Framework] { enabledFrameworks.filter { selectedFrameworkIDs.contains($0.id) } }
    private var fieldsApply: Bool { options.format != .pdf || options.requirementDetails }
    private var hasProfileFramework: Bool { selectedFrameworks.contains { !$0.document.tiers.isEmpty } }

    private var exportProblem: String? {
        if enabledFrameworks.isEmpty { return "Turn on a framework for this assessment first." }
        if selectedFrameworks.isEmpty { return "Choose at least one framework." }
        if options.format == .pdf && !options.pdfHasContent { return "Choose at least one section for the report." }
        return nil
    }

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
                formatSection
                frameworksSection
                requirementsSection
                if options.format == .pdf { pdfSectionsSection }
                includeSection
                createSection
                backupSection
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
            .onAppear(perform: load)
            .onChange(of: options) { _, new in
                storedOptions = new.encoded
                ready = nil
            }
            .onChange(of: selectedFrameworkIDs) { ready = nil }
            .accessibilityIdentifier("screen.export")
        }
    }

    // MARK: Sections

    /// The finished file, shown under the button that made it so it is never off screen.
    @ViewBuilder
    private func readyRows(for key: String) -> some View {
        if let ready, ready.key == key {
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
        }
    }

    private static let shareHint = "Choose Save to Files to keep a copy, or send it with AirDrop, Mail, or another app. The app does not keep exported copies."

    private var formatSection: some View {
        Section {
            ForEach(ExportFormat.allCases) { format in
                Button {
                    options.format = format
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                        Image(systemName: format.systemImage)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(format.title).font(.dsHeadline).foregroundStyle(Color.dsTextPrimary)
                            Text(format.detail).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .opacity(options.format == format ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(options.format == format ? .isSelected : [])
                .accessibilityIdentifier("format.\(format.rawValue)")
            }
        } header: {
            SectionHeader("Format")
        }
    }

    @ViewBuilder
    private var frameworksSection: some View {
        if enabledFrameworks.count > 1 {
            Section {
                if canCombine {
                    ForEach(enabledFrameworks) { fw in
                        Toggle(fw.document.shortName, isOn: Binding(
                            get: { selectedFrameworkIDs.contains(fw.id) },
                            set: { on in
                                if on { selectedFrameworkIDs.insert(fw.id) } else { selectedFrameworkIDs.remove(fw.id) }
                            }))
                        .accessibilityIdentifier("exportFramework.\(fw.id)")
                    }
                } else {
                    Picker("Framework", selection: Binding(
                        get: { selectedFrameworkIDs.first ?? enabledFrameworks.first?.id ?? "" },
                        set: { selectedFrameworkIDs = [$0] })) {
                        ForEach(enabledFrameworks) { fw in Text(fw.document.shortName).tag(fw.id) }
                    }
                }
            } header: {
                SectionHeader("Frameworks")
            }
        }
    }

    private var requirementsSection: some View {
        Section {
            Picker("Requirements", selection: $options.requirements) {
                ForEach(ExportRequirementFilter.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("exportRequirements")
        } footer: {
            Text(options.requirements.detail).font(.dsFootnote)
        }
    }

    private var pdfSectionsSection: some View {
        Section {
            Toggle("Summary and charts", isOn: $options.summary)
                .accessibilityIdentifier("section.summary")
            Toggle("What to do next", isOn: $options.nextSteps)
                .accessibilityIdentifier("section.nextSteps")
            Toggle("Requirement details", isOn: $options.requirementDetails)
                .accessibilityIdentifier("section.details")
        } header: {
            SectionHeader("Report sections")
        } footer: {
            Text("The cover page with the assessment name, frameworks, and disclaimer is always included.").font(.dsFootnote)
        }
    }

    private var includeSection: some View {
        Section {
            ForEach(ExportField.allCases) { field in
                if field != .profile || hasProfileFramework {
                    Toggle(isOn: Binding(get: { options.includes(field) },
                                         set: { options[keyPath: field.keyPath] = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.title)
                            Text(field.detail).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                        }
                    }
                    .accessibilityIdentifier("include.\(field.rawValue)")
                }
            }
        } header: {
            SectionHeader("Include")
        } footer: {
            Text(fieldsApply
                 ? "Turn off anything you do not want to share, such as internal notes. Requirement IDs, titles, and status are always included."
                 : "Turn on Requirement details to choose what each requirement shows.")
                .font(.dsFootnote)
        }
        .disabled(!fieldsApply)
    }

    private var createSection: some View {
        Section {
            actionButton(options.format.actionTitle, systemImage: options.format.systemImage, key: "create",
                         disabled: exportProblem != nil) {
                try makeExport()
            }
            readyRows(for: "create")
        } footer: {
            if let exportProblem {
                Text(exportProblem).font(.dsFootnote)
            } else if ready?.key == "create" {
                Text(Self.shareHint).font(.dsFootnote)
            }
        }
    }

    private var backupSection: some View {
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
                return Ready(key: "backup", url: url, title: "Backup ready", detail: url.lastPathComponent)
            }
            readyRows(for: "backup")
        } header: {
            SectionHeader("Encrypted backup")
        } footer: {
            Text("A complete copy for restoring on this or another device: every answer, note, and evidence file, encrypted with AES-256 using a key derived from your password. The choices above do not apply. Store the password somewhere safe: without it, the backup cannot be opened by anyone, including us.")
                .font(.dsFootnote)
        }
    }

    // MARK: Actions

    private func load() {
        options = ExportOptions.decode(storedOptions)
        if selectedFrameworkIDs.isEmpty {
            let ids = enabledFrameworks.map(\.id)
            selectedFrameworkIDs = canCombine ? Set(ids) : Set(ids.prefix(1))
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

    private func makeExport() throws -> Ready {
        let builder = ReportBuilder(assessment: assessment, frameworks: selectedFrameworks, options: options,
                                    graph: library.mappingGraph)
        let url = try builder.file()
        let title: String
        switch options.format {
        case .pdf: title = "Report ready"
        case .csv: title = "Spreadsheet ready"
        case .json: title = "Data file ready"
        }
        return Ready(key: "create", url: url, title: title, detail: url.lastPathComponent)
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
