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
            actionButton("Create Encrypted File", systemImage: "lock.doc", key: "backup", disabled: !canBackUp) {
                let url = try await BackupService(context: context).makeBackup(of: [assessment], password: password)
                password = ""
                confirmation = ""
                return Ready(key: "backup", url: url, title: "Encrypted file ready", detail: url.lastPathComponent)
            }
            readyRows(for: "backup")
        } header: {
            SectionHeader("Share with your team or move to a new device")
        } footer: {
            Text("A complete, encrypted copy of this assessment: every answer, note, and evidence file. The choices above do not apply. Send the file to teammates or your new device, and share the password separately, for example in person or by phone. They tap the file or use Import Assessment. When a teammate sends their copy back, importing it merges their updates with yours. Without the password, nobody can open the file, including us.")
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

/// Starts an import from anywhere in the app: the root view owns the file picker and the import sheet,
/// so buttons inside menus and lists can trigger it without presenting anything themselves.
@MainActor
@Observable
final class ImportCoordinator {
    var showingPicker = false
    var file: URL?

    func chooseFile() { showingPicker = true }
}

/// Opens an encrypted assessment file (from a teammate, another device, or a backup) and imports it.
struct ImportAssessmentView: View {
    let fileURL: URL
    var onImported: ((UUID) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var working = false
    @State private var errorMessage: String?
    @State private var payload: BackupPayload?
    @State private var existing: Set<UUID> = []
    @State private var modes: [UUID: BackupService.ImportMode] = [:]
    @State private var results: [BackupService.ImportResult]?

    var body: some View {
        NavigationStack {
            Form {
                if let results {
                    resultSections(results)
                } else if let payload {
                    contentSections(payload)
                } else {
                    passwordSection
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.dsCallout)
                            .foregroundStyle(Color.dsDestructive)
                    }
                }
            }
            .navigationTitle("Import Assessment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(results == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
            .accessibilityIdentifier("screen.import")
        }
    }

    private var passwordSection: some View {
        Section {
            Label(fileURL.lastPathComponent, systemImage: "lock.doc")
                .font(.dsBody)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit(open)
                .accessibilityIdentifier("restorePassword")
            Button {
                open()
            } label: {
                HStack {
                    Label("Open File", systemImage: "lock.open")
                    Spacer()
                    if working { ProgressView() }
                }
            }
            .disabled(password.isEmpty || working)
        } footer: {
            Text("Enter the password chosen when the file was created. Ask the person who sent it if you do not have it.")
                .font(.dsFootnote)
        }
    }

    @ViewBuilder
    private func contentSections(_ payload: BackupPayload) -> some View {
        ForEach(payload.archive.assessments, id: \.id) { a in
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(.dsHeadline)
                    if !a.organization.isEmpty {
                        Text(a.organization).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                    }
                    Text("\(a.responses.count) answers · \(a.evidence.count) evidence items · last changed \(a.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.dsFootnote)
                        .foregroundStyle(Color.dsTextSecondary)
                }
                if existing.contains(a.id) {
                    Picker("Already on this device", selection: Binding(
                        get: { modes[a.id] ?? .merge },
                        set: { modes[a.id] = $0 })) {
                        ForEach(BackupService.ImportMode.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("importMode")
                }
            } footer: {
                if existing.contains(a.id) {
                    Text((modes[a.id] ?? .merge).detail).font(.dsFootnote)
                }
            }
        }
        Section {
            Button {
                runImport(payload)
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .disabled(working)
            .accessibilityIdentifier("importConfirm")
        } footer: {
            Text("Created \(payload.archive.createdAt.formatted(date: .abbreviated, time: .shortened)) with version \(payload.archive.appVersion).")
                .font(.dsFootnote)
        }
    }

    @ViewBuilder
    private func resultSections(_ results: [BackupService.ImportResult]) -> some View {
        Section {
            ForEach(results) { r in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.dsHeadline)
                        Text(Self.describe(r.outcome)).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.dsImplemented)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("importResult")
            }
        } header: {
            SectionHeader("Imported")
        }
    }

    static func describe(_ outcome: BackupService.ImportOutcome) -> String {
        switch outcome {
        case .added: return "Added as a new assessment."
        case .addedCopy: return "Added alongside the existing assessment."
        case .replaced: return "Replaced the copy on this device."
        case .merged(let s):
            func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
            var parts: [String] = []
            if s.answersAdded > 0 { parts.append("\(count(s.answersAdded, "answer")) added") }
            if s.answersUpdated > 0 { parts.append("\(count(s.answersUpdated, "answer")) updated") }
            if s.evidenceAdded > 0 { parts.append("\(count(s.evidenceAdded, "evidence item")) added") }
            if s.valuesUpdated > 0 { parts.append("\(count(s.valuesUpdated, "organization-defined value")) updated") }
            var text = parts.isEmpty ? "Already up to date. Nothing new to import." : "Merged: \(parts.joined(separator: ", "))."
            if s.answersKeptNewer > 0 {
                text += " Kept \(count(s.answersKeptNewer, "newer answer")) from this device."
            }
            return text
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
                let service = BackupService(context: context)
                let decoded = try await service.decode(data, password: password)
                existing = service.existingIDs(in: decoded)
                payload = decoded
                password = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            working = false
        }
    }

    private func runImport(_ payload: BackupPayload) {
        working = true
        do {
            let imported = try BackupService(context: context).importAssessments(payload, modes: modes)
            results = imported
            if let first = imported.first { onImported?(first.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
        working = false
    }
}

/// "Import Assessment" button for lists, empty states, and Settings.
struct ImportAssessmentButton: View {
    var title = "Import Assessment"
    @Environment(ImportCoordinator.self) private var importer

    var body: some View {
        Button {
            importer.chooseFile()
        } label: {
            Label(title, systemImage: "square.and.arrow.down")
        }
        .accessibilityIdentifier("importAssessment")
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
