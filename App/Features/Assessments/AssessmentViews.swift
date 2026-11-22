import FrameworkKit
import SwiftData
import SwiftUI

/// Creates or edits an assessment: name, organization, frameworks, and the SP 800-53 baseline.
struct AssessmentEditorView: View {
    let assessment: Assessment?
    var onCreate: ((Assessment) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ContentLibrary.self) private var library
    @State private var name = ""
    @State private var organization = ""
    @State private var notes = ""
    @State private var enabled: Set<String> = ["csf-2.0"]
    @State private var scopes: [String: ScopeSelection] = [:]
    @State private var didLoad = false
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("For example: 2026 Security Review"))
                        .focused($nameFocused)
                        .accessibilityIdentifier("assessmentName")
                    TextField("Organization", text: $organization, prompt: Text("Organization or team (optional)"))
                    TextField("Notes", text: $notes, prompt: Text("Scope, systems covered, or other context (optional)"),
                              axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    SectionHeader("Assessment")
                }

                Section {
                    ForEach(library.entries) { entry in
                        Toggle(isOn: Binding(
                            get: { enabled.contains(entry.id) },
                            set: { on in if on { enabled.insert(entry.id) } else { enabled.remove(entry.id) } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.shortName).font(.dsBody)
                                Text(FrameworkFacts.countLine(entry)).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                            }
                        }
                        .accessibilityIdentifier("enable.\(entry.id)")
                    }
                } header: {
                    SectionHeader("Frameworks")
                } footer: {
                    Text("You can change these at any time. Turning a framework off keeps its answers.").font(.dsFootnote)
                }

                ForEach(library.entries.filter { enabled.contains($0.id) && !$0.baselines.isEmpty }) { entry in
                    Section {
                        Picker("Baseline", selection: Binding(
                            get: { scopes[entry.id]?.baselineID ?? "" },
                            set: { id in
                                var s = scopes[entry.id] ?? ScopeSelection()
                                s.baselineID = id.isEmpty ? nil : id
                                scopes[entry.id] = s
                            }
                        )) {
                            ForEach(entry.baselines.filter { !$0.additive }) { b in
                                Text("\(b.title) (\(entry.counts.total(inBaseline: b.id)))").tag(b.id)
                            }
                            Text("Full catalog (\(entry.counts.requirements))").tag("")
                        }
                        ForEach(entry.baselines.filter(\.additive)) { b in
                            Toggle("Add \(b.title) baseline (\(entry.counts.total(inBaseline: b.id)))", isOn: Binding(
                                get: { scopes[entry.id]?.additiveBaselineIDs.contains(b.id) ?? false },
                                set: { on in
                                    var s = scopes[entry.id] ?? ScopeSelection()
                                    if on { s.additiveBaselineIDs.insert(b.id) } else { s.additiveBaselineIDs.remove(b.id) }
                                    scopes[entry.id] = s
                                }
                            ))
                        }
                    } header: {
                        SectionHeader("\(entry.shortName) baseline")
                    } footer: {
                        Text("Moderate is the most common choice. Add the Privacy baseline if your systems process personal information.")
                            .font(.dsFootnote)
                    }
                }
            }
            .navigationTitle(assessment == nil ? "New Assessment" : "Edit Assessment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(assessment == nil ? "Create" : "Save") { save() }
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier("saveAssessment")
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let a = assessment {
            name = a.name
            organization = a.organization
            notes = a.notes
            enabled = Set(a.enabledFrameworkIDs)
            scopes = a.scopes
        } else {
            for entry in library.entries where !entry.baselines.isEmpty {
                let moderate = entry.baselines.first { $0.id == "moderate" } ?? entry.baselines.first { !$0.additive }
                scopes[entry.id] = ScopeSelection(baselineID: moderate?.id)
            }
            nameFocused = true
        }
    }

    private func save() {
        let ordered = library.frameworkOrder.filter(enabled.contains)
        if let a = assessment {
            a.name = trimmedName
            a.organization = organization.trimmingCharacters(in: .whitespacesAndNewlines)
            a.notes = notes
            a.enabledFrameworkIDs = ordered
            var merged = a.scopes
            for (k, v) in scopes {
                var s = merged[k] ?? ScopeSelection()
                s.baselineID = v.baselineID
                s.additiveBaselineIDs = v.additiveBaselineIDs
                merged[k] = s
            }
            a.scopes = merged
            a.touch()
        } else {
            let created = AssessmentService(context: context).createAssessment(
                name: trimmedName, organization: organization, frameworkIDs: ordered, scopes: scopes)
            created.notes = notes
            onCreate?(created)
        }
        dismiss()
    }
}

/// All assessments on this device.
struct AssessmentListView: View {
    let current: Assessment?
    var selection: Binding<AppRoute?>?
    @Binding var showingNewAssessment: Bool
    let selectAssessment: (Assessment) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Assessment.updatedAt, order: .reverse) private var assessments: [Assessment]
    @State private var pendingDeletion: Assessment?
    @State private var editing: Assessment?

    var body: some View {
        Group {
            if assessments.isEmpty {
                NoAssessmentView(showingNewAssessment: $showingNewAssessment)
            } else if let selection {
                List(selection: selection) { rows }
            } else {
                List { rows }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Assessments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewAssessment = true } label: { Label("New Assessment", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { a in AssessmentEditorView(assessment: a) }
        .confirmationDialog("Delete this assessment?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible, presenting: pendingDeletion) { a in
            Button("Delete \(a.name)", role: .destructive) { AssessmentService(context: context).delete(a) }
        } message: { _ in
            Text("All answers, notes, and evidence files in this assessment are permanently removed from this device. Export a backup first if you may need them.")
        }
    }

    private var rows: some View {
        ForEach(assessments) { a in
            NavigationLink(value: AppRoute.assessment(a.id)) {
                AssessmentRow(assessment: a, isCurrent: a.id == current?.id)
            }
            .swipeActions {
                Button(role: .destructive) { pendingDeletion = a } label: { Label("Delete", systemImage: "trash") }
                Button { duplicate(a) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .tint(.dsAccent)
            }
            .contextMenu {
                Button { selectAssessment(a) } label: { Label("Make Current", systemImage: "checkmark.circle") }
                Button { editing = a } label: { Label("Edit", systemImage: "pencil") }
                Button { duplicate(a) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Divider()
                Button(role: .destructive) { pendingDeletion = a } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func duplicate(_ a: Assessment) {
        let copy = AssessmentService(context: context).duplicate(a, name: "\(a.name) (Copy)")
        selectAssessment(copy)
    }
}

private struct AssessmentRow: View {
    let assessment: Assessment
    let isCurrent: Bool
    @Environment(ContentLibrary.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(assessment.name).font(.dsHeadline).foregroundStyle(Color.dsTextPrimary)
                if isCurrent {
                    Text("Current").font(.dsFootnote.weight(.medium)).foregroundStyle(Color.dsAccent)
                }
                Spacer()
            }
            if !assessment.organization.isEmpty {
                Text(assessment.organization).font(.dsSubheadline).foregroundStyle(Color.dsTextSecondary)
            }
            Text(detailLine).font(.dsFootnote).foregroundStyle(Color.dsTextTertiary)
        }
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        let names = assessment.enabledFrameworkIDs.compactMap { library.entry($0)?.shortName }
        let updated = "Updated \(assessment.updatedAt.formatted(date: .abbreviated, time: .omitted))"
        return names.isEmpty ? updated : names.joined(separator: ", ") + " · " + updated
    }
}

/// Summary of one assessment with its frameworks and progress.
struct AssessmentDetailView: View {
    @Bindable var assessment: Assessment
    @Environment(ContentLibrary.self) private var library
    @State private var editing = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(assessment.name).font(.dsTitle2).foregroundStyle(Color.dsTextPrimary)
                    if !assessment.organization.isEmpty {
                        Text(assessment.organization).font(.dsCallout).foregroundStyle(Color.dsTextSecondary)
                    }
                    if !assessment.notes.isEmpty {
                        Text(assessment.notes).font(.dsBody).foregroundStyle(Color.dsTextPrimary).padding(.top, DS.Space.xxs)
                    }
                }
                .padding(.vertical, DS.Space.xxs)
                KeyValueRow(label: "Created", value: assessment.createdAt.formatted(date: .abbreviated, time: .omitted))
                KeyValueRow(label: "Last updated", value: assessment.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section {
                let enabled = library.entries.filter { assessment.isEnabled($0.id) }
                if enabled.isEmpty {
                    Text("No frameworks are turned on.").font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                }
                ForEach(enabled) { entry in
                    if let fw = library.framework(entry.id) {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            EnabledFrameworkRow(entry: entry, progress: assessment.progress(for: fw))
                            if fw.hasBaselines {
                                Text(ScopeDescription.short(assessment.scope(for: fw.id), framework: fw))
                                    .font(.dsFootnote)
                                    .foregroundStyle(Color.dsTextSecondary)
                            }
                        }
                    }
                }
            } header: {
                SectionHeader("Frameworks")
            }

            Section {
                KeyValueRow(label: "Evidence items", value: "\(assessment.evidence.count)")
                KeyValueRow(label: "Answered requirements", value: "\(assessment.responses.filter { $0.status != .notStarted }.count)")
            } header: {
                SectionHeader("Contents")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(assessment.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
        }
        .sheet(isPresented: $editing) { AssessmentEditorView(assessment: assessment) }
    }
}
