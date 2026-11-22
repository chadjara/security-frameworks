import FrameworkKit
import SwiftUI

/// Shows what the bundled content contains and whether it validates. Used to verify Phase 1 data
/// on a device; replaced by the framework explorer in Phase 2.
struct ContentOverviewView: View {
    struct Snapshot {
        let index: ContentIndex
        let errors: [ValidationIssue]
        let warnings: [ValidationIssue]
    }

    @State private var state: LoadState<Snapshot> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingStateView(message: "Loading framework content")
            case .failed(let message):
                ErrorStateView(title: "Content could not be loaded", message: message) { Task { await load() } }
            case .loaded(let snapshot):
                list(snapshot)
            }
        }
        .navigationTitle("Framework Content")
        .accessibilityIdentifier("screen.content")
        .task { await load() }
    }

    private func list(_ snapshot: Snapshot) -> some View {
        List {
            Section {
                Label {
                    Text(snapshot.errors.isEmpty ? "All content passed validation" : "\(snapshot.errors.count) validation errors")
                        .font(.dsHeadline)
                } icon: {
                    Image(systemName: snapshot.errors.isEmpty ? "checkmark.seal" : "exclamationmark.triangle")
                        .foregroundStyle(snapshot.errors.isEmpty ? Color.dsImplemented : Color.dsDestructive)
                }
                KeyValueRow(label: "Content version", value: snapshot.index.contentVersion)
                KeyValueRow(label: "Warnings", value: "\(snapshot.warnings.count)")
            } header: {
                SectionHeader("Validation")
            }

            ForEach(snapshot.index.frameworks) { entry in
                Section {
                    Text(entry.title).font(.dsBody).foregroundStyle(Color.dsTextSecondary)
                    ForEach(entry.kinds) { kind in
                        KeyValueRow(label: kind.plural, value: "\(entry.counts.byKind[kind.id] ?? 0)")
                    }
                    ForEach(Array(zip(entry.groupLevels, entry.counts.groups)), id: \.0.plural) { level, count in
                        KeyValueRow(label: level.plural, value: "\(count)")
                    }
                    ForEach(entry.baselines) { baseline in
                        KeyValueRow(label: "\(baseline.title) baseline", value: "\(entry.counts.total(inBaseline: baseline.id))")
                    }
                    KeyValueRow(label: "Organization-defined parameters", value: "\(entry.counts.parameters)")
                } header: {
                    SectionHeader(entry.shortName)
                }
            }

            Section {
                ForEach(snapshot.index.mappings) { mapping in
                    KeyValueRow(label: Self.mappingLabel(mapping, index: snapshot.index), value: "\(mapping.pairs)")
                }
            } header: {
                SectionHeader("Published mappings")
            } footer: {
                Text("Pairs published by NIST. No mapping is inferred.").font(.dsFootnote)
            }
        }
        .listStyle(.insetGrouped)
    }

    static func mappingLabel(_ m: MappingIndexEntry, index: ContentIndex) -> String {
        let name = { (id: String) in index.frameworks.first { $0.id == id }?.shortName ?? id }
        return "\(name(m.fromFramework)) → \(name(m.toFramework))"
    }

    private func load() async {
        state = .loading
        guard let store = FrameworkStore.bundled() else {
            state = .failed("The framework content folder is missing from the app.")
            return
        }
        do {
            let index = try await store.index()
            let issues = try await store.validateAll()
            state = .loaded(Snapshot(index: index,
                                     errors: issues.filter { $0.severity == .error },
                                     warnings: issues.filter { $0.severity == .warning }))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
