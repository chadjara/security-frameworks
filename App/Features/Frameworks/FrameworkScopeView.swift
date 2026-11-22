import FrameworkKit
import SwiftData
import SwiftUI

enum ScopeDescription {
    /// "Moderate + Privacy · 2 added"
    static func short(_ scope: ScopeSelection, framework: Framework) -> String {
        guard framework.hasBaselines else { return "All requirements" }
        var parts: [String] = []
        if let base = scope.baselineID, let b = framework.baseline(base) { parts.append(b.title) }
        for id in scope.additiveBaselineIDs.sorted() { if let b = framework.baseline(id) { parts.append(b.title) } }
        var text = parts.isEmpty ? "Full catalog" : parts.joined(separator: " + ")
        if !scope.addedRequirementIDs.isEmpty, scope.usesBaselines { text += " · \(scope.addedRequirementIDs.count) added" }
        return text
    }
}

/// SP 800-53B baseline selection and manual additions for one framework in an assessment.
struct FrameworkScopeView: View {
    @Bindable var assessment: Assessment
    let framework: Framework
    @Environment(ContentLibrary.self) private var library
    @State private var showingAddSheet = false

    private var scope: ScopeSelection { assessment.scope(for: framework.id) }
    private var baseBaselines: [Baseline] { framework.document.baselines.filter { !$0.additive } }
    private var additiveBaselines: [Baseline] { framework.document.baselines.filter(\.additive) }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { assessment.isEnabled(framework.id) },
                    set: { assessment.setEnabled(framework.id, $0, order: library.frameworkOrder) }
                )) {
                    Text("Use \(framework.document.shortName)").font(.dsBody)
                }
            } footer: {
                Text("Turning a framework off hides it. Your answers and evidence are kept.").font(.dsFootnote)
            }

            ForEach(framework.document.notices) { notice in
                Section { NoticeView(title: notice.title, message: notice.body) }
            }

            if framework.hasBaselines {
                Section {
                    ForEach(baseBaselines) { b in
                        baselineRow(title: b.title, summary: b.summary, count: count(base: b.id),
                                    selected: scope.baselineID == b.id) { setBase(b.id) }
                    }
                    baselineRow(title: "Full catalog", summary: "Every control and enhancement, without a baseline.",
                                count: framework.requirements.count,
                                selected: scope.baselineID == nil && scope.additiveBaselineIDs.isEmpty) { setBase(nil, clearAdditive: true) }
                } header: {
                    SectionHeader("Baseline")
                } footer: {
                    Text("Baselines come from NIST SP 800-53B. Choose the one that matches the impact level of your system.")
                        .font(.dsFootnote)
                }

                if !additiveBaselines.isEmpty {
                    Section {
                        ForEach(additiveBaselines) { b in
                            Toggle(isOn: Binding(
                                get: { scope.additiveBaselineIDs.contains(b.id) },
                                set: { on in
                                    var s = scope
                                    if on { s.additiveBaselineIDs.insert(b.id) } else { s.additiveBaselineIDs.remove(b.id) }
                                    assessment.setScope(s, for: framework.id)
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(b.title) baseline").font(.dsBody)
                                    if let summary = b.summary {
                                        Text(summary).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        SectionHeader("Add to the baseline")
                    }
                }

                Section {
                    let added = scope.addedRequirementIDs.compactMap(framework.requirement).sorted { $0.sortKey < $1.sortKey }
                    if added.isEmpty {
                        Text("No controls added. Add controls outside your baseline when your organization needs them.")
                            .font(.dsFootnote)
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                    ForEach(added) { r in
                        RequirementRow(displayID: r.displayId, title: r.title)
                            .swipeActions {
                                Button(role: .destructive) { remove(r.id) } label: { Label("Remove", systemImage: "minus.circle") }
                            }
                    }
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Controls", systemImage: "plus.circle")
                    }
                    .disabled(!scope.usesBaselines)
                } header: {
                    SectionHeader("Added controls")
                } footer: {
                    Text("\(framework.requirementsInScope(scope).count) controls and enhancements are in scope.")
                        .font(.dsFootnote.monospacedDigit())
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Baseline and Scope")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddSheet) {
            AddRequirementsSheet(framework: framework, candidates: framework.requirementsOutOfScope(scope)) { ids in
                var s = scope
                s.addedRequirementIDs.formUnion(ids)
                assessment.setScope(s, for: framework.id)
            }
        }
        .accessibilityIdentifier("screen.scope")
    }

    private func baselineRow(title: String, summary: String?, count: Int, selected: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.s) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.dsAccent : Color.dsTextTertiary)
                    .font(.dsBody)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.dsBody).foregroundStyle(Color.dsTextPrimary)
                        Spacer()
                        Text("\(count)").font(.dsFootnote.monospacedDigit()).foregroundStyle(Color.dsTextSecondary)
                    }
                    if let summary {
                        Text(summary).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private func count(base: String) -> Int {
        framework.requirements.filter { $0.baselines.contains(base) }.count
    }

    private func setBase(_ id: String?, clearAdditive: Bool = false) {
        var s = scope
        s.baselineID = id
        if clearAdditive { s.additiveBaselineIDs = [] }
        assessment.setScope(s, for: framework.id)
    }

    private func remove(_ id: String) {
        var s = scope
        s.addedRequirementIDs.remove(id)
        assessment.setScope(s, for: framework.id)
    }
}

/// Searchable multi-select of requirements outside the current scope.
struct AddRequirementsSheet: View {
    let framework: Framework
    let candidates: [Requirement]
    let onAdd: (Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var picked: Set<String> = []

    private var filtered: [Requirement] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return candidates }
        return candidates.filter { $0.displayId.lowercased().contains(q) || $0.title.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { r in
                Button {
                    if picked.contains(r.id) { picked.remove(r.id) } else { picked.insert(r.id) }
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: picked.contains(r.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(picked.contains(r.id) ? Color.dsAccent : Color.dsTextTertiary)
                        RequirementRow(displayID: r.displayId, title: r.title)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(picked.contains(r.id) ? .isSelected : [])
            }
            .overlay {
                if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search controls")
            .navigationTitle("Add Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.isEmpty ? "Add" : "Add \(picked.count)") {
                        onAdd(picked)
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
            }
        }
    }
}
