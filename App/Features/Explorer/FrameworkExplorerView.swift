import FrameworkKit
import SwiftData
import SwiftUI

/// Every installed framework, described in plain language.
struct FrameworkExplorerView: View {
    let assessment: Assessment?
    var selection: Binding<AppRoute?>?
    @Environment(ContentLibrary.self) private var library

    var body: some View {
        Group {
            if let selection {
                List(selection: selection) { rows }
            } else {
                List { rows }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Explore Frameworks")
        .accessibilityIdentifier("screen.explorer")
    }

    @ViewBuilder
    private var rows: some View {
        Section {
            ForEach(library.entries) { entry in
                NavigationLink(value: AppRoute.frameworkPreview(frameworkID: entry.id)) {
                    ExplorerRow(entry: entry, isEnabled: assessment?.isEnabled(entry.id) == true)
                }
                .accessibilityIdentifier("explorer.\(entry.id)")
            }
        } footer: {
            Text("Framework content comes from NIST's published data. This app is independent and not affiliated with or endorsed by NIST.")
                .font(.dsFootnote)
        }
    }
}

private struct ExplorerRow: View {
    let entry: FrameworkIndexEntry
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.shortName).font(.dsHeadline).foregroundStyle(Color.dsTextPrimary)
                Spacer(minLength: DS.Space.xs)
                if isEnabled {
                    Label("On", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.dsFootnote.weight(.medium))
                        .foregroundStyle(Color.dsImplemented)
                        .accessibilityLabel("Turned on for this assessment")
                }
            }
            Text(entry.title).font(.dsSubheadline).foregroundStyle(Color.dsTextSecondary)
            if let summary = entry.summary {
                Text(summary.plainDescription)
                    .font(.dsFootnote)
                    .foregroundStyle(Color.dsTextSecondary)
                    .lineLimit(3)
            }
            Text(FrameworkFacts.countLine(entry))
                .font(.dsFootnote.monospacedDigit())
                .foregroundStyle(Color.dsTextTertiary)
        }
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

enum FrameworkFacts {
    /// "106 subcategories · 6 functions · 22 categories"
    static func countLine(_ entry: FrameworkIndexEntry) -> String {
        var parts = entry.kinds.map { kind in
            "\(entry.counts.byKind[kind.id] ?? 0) \(kind.plural.lowercased())"
        }
        for (level, count) in zip(entry.groupLevels, entry.counts.groups) {
            parts.append("\(count) \(level.plural.lowercased())")
        }
        return parts.joined(separator: " · ")
    }
}

/// A framework's plain-language profile, its structure, and the switch to use it.
struct FrameworkPreviewView: View {
    let entry: FrameworkIndexEntry
    let framework: Framework
    let assessment: Assessment?
    @Environment(ContentLibrary.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text(entry.shortName).font(.dsTitle).foregroundStyle(Color.dsTextPrimary)
                        .dsDisplayTypeCap()
                    Text(entry.title).font(.dsCallout).foregroundStyle(Color.dsTextSecondary)
                    if let summary = entry.summary {
                        Text(summary.plainDescription).font(.dsBody).foregroundStyle(Color.dsTextPrimary)
                            .padding(.top, DS.Space.xxs)
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }

            ForEach(entry.notices) { notice in
                Section { NoticeView(title: notice.title, message: notice.body) }
            }

            if let assessment {
                Section {
                    Toggle(isOn: Binding(
                        get: { assessment.isEnabled(entry.id) },
                        set: { assessment.setEnabled(entry.id, $0, order: library.frameworkOrder) }
                    )) {
                        Text("Use in \(assessment.name)").font(.dsBody)
                    }
                    .accessibilityIdentifier("toggle.\(entry.id)")
                    if assessment.isEnabled(entry.id) && framework.hasBaselines {
                        NavigationLink(value: AppRoute.frameworkSettings(frameworkID: entry.id)) {
                            KeyValueRow(label: "Baseline and scope", value: ScopeDescription.short(assessment.scope(for: entry.id), framework: framework))
                        }
                    }
                } header: {
                    SectionHeader("In this assessment")
                } footer: {
                    Text("Turning a framework off hides it from this assessment. Your answers and evidence are kept and return when you turn it back on.")
                        .font(.dsFootnote)
                }
            }

            if let summary = entry.summary {
                Section {
                    FactRow(title: "Who it is for", text: summary.audience)
                    FactRow(title: "What it covers", text: summary.covers)
                    FactRow(title: "Typical effort", text: summary.typicalEffort)
                    FactRow(title: "When to choose it", text: summary.whenToChoose)
                } header: {
                    SectionHeader("At a glance")
                }
            }

            Section {
                ForEach(entry.kinds) { kind in
                    KeyValueRow(label: kind.plural, value: "\(entry.counts.byKind[kind.id] ?? 0)")
                }
                ForEach(Array(zip(entry.groupLevels, entry.counts.groups)), id: \.0.plural) { level, count in
                    KeyValueRow(label: level.plural, value: "\(count)")
                }
                ForEach(entry.baselines) { b in
                    KeyValueRow(label: "\(b.title) baseline", value: "\(entry.counts.total(inBaseline: b.id))")
                }
                if entry.counts.parameters > 0 {
                    KeyValueRow(label: "Organization-defined values", value: "\(entry.counts.parameters)")
                }
            } header: {
                SectionHeader("Size")
            }

            Section {
                ForEach(framework.groups) { group in
                    StructureRow(framework: framework, group: group)
                }
            } header: {
                SectionHeader("Structure")
            } footer: {
                Text("Select a \(entry.groupLevels.last?.singular.lowercased() ?? "group") to preview its requirements.")
                    .font(.dsFootnote)
            }

            Section {
                let source = framework.document.source
                KeyValueRow(label: "Publication", value: framework.document.publicationId)
                KeyValueRow(label: "Version", value: source.catalogVersion.map { "Release \($0)" } ?? framework.document.version)
                if let modified = source.lastModified?.prefix(10) {
                    KeyValueRow(label: "NIST data updated", value: String(modified))
                }
                if let s = source.publicationUrl, let url = URL(string: s) {
                    Link(destination: url) { Label("Read the publication", systemImage: "arrow.up.right.square") }
                }
            } header: {
                SectionHeader("Source")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.frameworkPreview")
    }
}

private struct FactRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(title).font(.dsSubheadline.weight(.semibold)).foregroundStyle(Color.dsTextPrimary)
            Text(text).font(.dsBody).foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// A top-level group with its subgroups (CSF) or a direct link to its requirements.
private struct StructureRow: View {
    let framework: Framework
    let group: RequirementGroup

    var body: some View {
        if group.isLeaf {
            NavigationLink(value: AppRoute.groupPreview(frameworkID: framework.id, groupID: group.id)) {
                label(for: group)
            }
        } else {
            DisclosureGroup {
                ForEach(group.groups) { sub in
                    NavigationLink(value: AppRoute.groupPreview(frameworkID: framework.id, groupID: sub.id)) {
                        label(for: sub)
                    }
                }
            } label: {
                label(for: group)
            }
        }
    }

    private func label(for g: RequirementGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(g.displayId).font(.dsRequirementID).foregroundStyle(Color.dsAccent)
                .frame(minWidth: 48, alignment: .leading)
            Text(g.title).font(.dsBody).foregroundStyle(Color.dsTextPrimary)
            Spacer(minLength: DS.Space.xs)
            Text("\(framework.requirements(inGroup: g.id).count)")
                .font(.dsFootnote.monospacedDigit())
                .foregroundStyle(Color.dsTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Read-only list of a group's requirements, for previewing a framework before using it.
struct GroupPreviewView: View {
    let framework: Framework
    let groupID: String

    var body: some View {
        let group = framework.group(groupID)
        List {
            if let description = group?.description {
                Section { Text(description).font(.dsCallout).foregroundStyle(Color.dsTextSecondary) }
            }
            Section {
                ForEach(framework.requirements(inGroup: groupID)) { r in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        RequirementIDLabel(id: r.displayId, size: .small)
                        Text(r.title).font(.dsBody).foregroundStyle(Color.dsTextPrimary)
                        if let q = r.editorial?.question {
                            Text(q).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                        }
                    }
                    .padding(.leading, r.parentId == nil ? 0 : DS.Space.s)
                    .padding(.vertical, DS.Space.xxs)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(group.map { "\($0.displayId) \($0.title)" } ?? "Requirements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
