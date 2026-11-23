import FrameworkKit
import SwiftData
import SwiftUI

/// A NIST-published link from the current requirement to one in another framework.
struct ResolvedLink: Identifiable, Hashable {
    let link: MappingLink
    let framework: Framework
    let requirement: Requirement

    var id: RequirementRef { link.target }

    var relationshipLabel: String {
        switch (link.relationship, link.direction) {
        case (.sourceControl, .forward): return "Source control"
        case (.sourceControl, .reverse): return "Derived requirement"
        case (.informativeReference, .forward): return "Informative reference"
        case (.informativeReference, .reverse): return "Referenced by CSF"
        default: return "Related"
        }
    }

    static func == (a: ResolvedLink, b: ResolvedLink) -> Bool { a.link == b.link }
    func hash(into hasher: inout Hasher) { hasher.combine(link) }
}

enum MappingResolver {
    /// Links to requirements in enabled frameworks, de-duplicated by target, in framework order.
    @MainActor
    static func links(for ref: RequirementRef, assessment: Assessment, library: ContentLibrary) -> [ResolvedLink] {
        guard let graph = library.mappingGraph else { return [] }
        let enabled = Set(assessment.enabledFrameworkIDs)
        var seen = Set<RequirementRef>()
        var out: [ResolvedLink] = []
        for link in graph.links(from: ref, enabledFrameworks: enabled) where seen.insert(link.target).inserted {
            guard let fw = library.framework(link.target.frameworkID),
                  let r = fw.requirement(link.target.requirementID) else { continue }
            out.append(ResolvedLink(link: link, framework: fw, requirement: r))
        }
        let order = library.frameworkOrder
        return out.sorted {
            let a = order.firstIndex(of: $0.framework.id) ?? 0, b = order.firstIndex(of: $1.framework.id) ?? 0
            if a != b { return a < b }
            return $0.requirement.sortKey < $1.requirement.sortKey
        }
    }

    /// Frameworks that are turned off but hold published links for this requirement.
    @MainActor
    static func hiddenFrameworkCounts(for ref: RequirementRef, assessment: Assessment, library: ContentLibrary) -> [(String, Int)] {
        guard let graph = library.mappingGraph else { return [] }
        let all = graph.links(from: ref)
        let grouped = Dictionary(grouping: all.filter { !assessment.isEnabled($0.target.frameworkID) }, by: \.target.frameworkID)
        return grouped.compactMap { id, links in
            library.entry(id).map { ($0.shortName, Set(links.map(\.target)).count) }
        }.sorted { $0.0 < $1.0 }
    }
}

/// Related requirements in other enabled frameworks, with the option to reuse this answer.
struct MappedRequirementsSection: View {
    @Bindable var assessment: Assessment
    let framework: Framework
    let requirement: Requirement
    @Environment(ContentLibrary.self) private var library
    @State private var showingApply = false

    private var ref: RequirementRef { RequirementRef(frameworkID: framework.id, requirementID: requirement.id) }

    var body: some View {
        let links = MappingResolver.links(for: ref, assessment: assessment, library: library)
        let hidden = MappingResolver.hiddenFrameworkCounts(for: ref, assessment: assessment, library: library)
        if !links.isEmpty || !hidden.isEmpty {
            Section {
                ForEach(links) { item in
                    NavigationLink(value: AppRoute.requirement(frameworkID: item.framework.id, requirementID: item.requirement.id)) {
                        MappedRow(item: item, status: assessment.status(for: item.link.target))
                    }
                }
                if !links.isEmpty {
                    Button {
                        showingApply = true
                    } label: {
                        Label("Apply This Answer to Related Requirements", systemImage: "arrow.triangle.branch")
                    }
                    .disabled(assessment.status(for: ref) == .notStarted)
                    .accessibilityIdentifier("applyToMapped")
                    .sheet(isPresented: $showingApply) {
                        ApplyToMappedSheet(assessment: assessment, source: ref, sourceLabel: "\(framework.document.shortName) \(requirement.displayId)",
                                           links: links)
                    }
                }
                ForEach(hidden, id: \.0) { name, count in
                    Text("Turn on \(name) to see \(count) related requirement\(count == 1 ? "" : "s").")
                        .font(.dsFootnote)
                        .foregroundStyle(Color.dsTextSecondary)
                }
            } header: {
                SectionHeader("Related requirements")
            } footer: {
                Text("Relationships come only from mappings NIST publishes. A related requirement may cover more or less than this one, so review each before relying on a shared answer.")
                    .font(.dsFootnote)
            }
        }
    }
}

private struct MappedRow: View {
    let item: ResolvedLink
    let status: RequirementStatus

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Text(item.framework.document.shortName)
                    .font(.dsFootnote.weight(.medium))
                    .foregroundStyle(Color.dsTextSecondary)
                RequirementIDLabel(id: item.requirement.displayId, size: .small)
                Spacer(minLength: DS.Space.xs)
                Image(systemName: status.symbolName)
                    .foregroundStyle(status.color)
                    .accessibilityLabel(status.title)
            }
            Text(item.requirement.title)
                .font(.dsBody)
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(3)
            Text(item.relationshipLabel)
                .font(.dsFootnote)
                .foregroundStyle(Color.dsTextTertiary)
        }
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// Confirms which related requirements receive this answer, and what is copied.
struct ApplyToMappedSheet: View {
    @Bindable var assessment: Assessment
    let source: RequirementRef
    let sourceLabel: String
    let links: [ResolvedLink]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selected: Set<RequirementRef> = []
    @State private var options = AssessmentService.ApplyOptions()
    @State private var confirming = false
    @State private var didLoad = false

    private var sourceResponse: RequirementResponse? { assessment.response(for: source) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NoticeView(title: "Check each requirement",
                               message: "NIST's mappings show related requirements, not identical ones. Select only the requirements this answer genuinely satisfies, then review them afterward.",
                               systemImage: "exclamationmark.triangle")
                }

                Section {
                    if let s = sourceResponse {
                        StatusBadge(status: s.status, style: .tinted)
                        if s.status == .notApplicable, !s.notApplicableReason.isEmpty {
                            Text(s.notApplicableReason).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                        }
                    }
                } header: {
                    SectionHeader("Answer from \(sourceLabel)")
                }

                Section {
                    Toggle("Status", isOn: $options.status)
                    Toggle("Owner and target date (where empty)", isOn: $options.ownerAndDate)
                    Toggle("Notes (added, with attribution)", isOn: $options.notes)
                    let evidenceCount = sourceResponse?.evidence.count ?? 0
                    if evidenceCount > 0 {
                        Toggle("Evidence (\(evidenceCount) item\(evidenceCount == 1 ? "" : "s"), shared)", isOn: $options.evidence)
                    }
                } header: {
                    SectionHeader("What to apply")
                } footer: {
                    if (sourceResponse?.evidence.count ?? 0) > 0 {
                        Text("Evidence is shared, not copied: the same files and notes appear on each requirement.").font(.dsFootnote)
                    }
                }

                Section {
                    ForEach(links) { item in
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                        } label: {
                            HStack(alignment: .top, spacing: DS.Space.s) {
                                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(item.id) ? Color.dsAccent : Color.dsTextTertiary)
                                    .font(.dsBody)
                                MappedRow(item: item, status: assessment.status(for: item.id))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
                    }
                } header: {
                    SectionHeader("Apply to")
                } footer: {
                    Text("Requirements that are not started are selected for you. Requirements with an answer are not, so you do not overwrite work by accident.")
                        .font(.dsFootnote)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Apply Answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Apply" : "Apply to \(selected.count)") { confirming = true }
                        .disabled(selected.isEmpty || options == AssessmentService.ApplyOptions(status: false, ownerAndDate: false, notes: false, evidence: false))
                }
            }
            .confirmationDialog("Apply this answer to \(selected.count) requirement\(selected.count == 1 ? "" : "s")?",
                                isPresented: $confirming, titleVisibility: .visible) {
                Button("Apply") {
                    let targets = links.map(\.id).filter(selected.contains)
                    AssessmentService(context: context).apply(from: source, sourceLabel: sourceLabel, to: targets,
                                                             options: options, in: assessment)
                    dismiss()
                }
            } message: {
                Text("Each selected requirement is marked as applied from \(sourceLabel). You can change any of them afterward.")
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                selected = Set(links.map(\.id).filter { assessment.status(for: $0) == .notStarted })
            }
        }
    }
}
