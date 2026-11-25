import FrameworkKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// App root: loads content, tracks the current assessment, and picks the iPad split view or the
/// iPhone tab layout.
struct RootView: View {
    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Assessment.createdAt) private var assessments: [Assessment]
    @AppStorage("selectedAssessmentID") private var selectedAssessmentID = ""
    @State private var showingNewAssessment = false
    @State private var didApplyLaunchRoute = false
    /// One per window, so an import started in one window does not appear in another.
    @State private var importer = ImportCoordinator()

    private var currentAssessment: Assessment? {
        assessments.first { $0.id.uuidString == selectedAssessmentID } ?? assessments.first
    }

    var body: some View {
        Group {
            switch library.phase {
            case .idle, .loading:
                LoadingStateView(message: "Loading frameworks")
            case .failed(let message):
                ErrorStateView(title: "Framework content could not be loaded", message: message) {
                    Task { await library.load() }
                }
            case .ready:
                if horizontalSizeClass == .compact {
                    CompactRootView(assessment: currentAssessment, showingNewAssessment: $showingNewAssessment,
                                    selectAssessment: select)
                } else {
                    RegularRootView(assessment: currentAssessment, showingNewAssessment: $showingNewAssessment,
                                    selectAssessment: select)
                }
            }
        }
        .task {
            await library.loadIfNeeded()
            seedIfRequested()
        }
        .sheet(isPresented: $showingNewAssessment) {
            AssessmentEditorView(assessment: nil) { created in select(created) }
        }
        .onOpenURL { url in
            if url.pathExtension.lowercased() == "fwbackup" { importer.file = url }
        }
        .fileImporter(isPresented: $importer.showingPicker, allowedContentTypes: [.fwBackup, .data]) { result in
            if case .success(let url) = result { importer.file = url }
        }
        .sheet(item: $importer.file) { url in
            ImportAssessmentView(fileURL: url) { id in
                if let imported = try? context.fetch(FetchDescriptor<Assessment>()).first(where: { $0.id == id }) {
                    select(imported)
                }
            }
        }
        .environment(importer)
    }

    private func select(_ assessment: Assessment) {
        selectedAssessmentID = assessment.id.uuidString
    }

    private func seedIfRequested() {
        #if DEBUG
        guard !didApplyLaunchRoute, let scenario = LaunchOptions.seedScenario, library.phase == .ready else { return }
        didApplyLaunchRoute = true
        if let seeded = UITestSeed.apply(scenario, context: context, library: library) { select(seeded) }
        if UITestRoute.current == .newAssessment { showingNewAssessment = true }
        if UITestRoute.current == .importFile { presentSampleImport() }
        #endif
    }

    #if DEBUG
    /// Encrypts the seeded assessment with a known password and opens the import sheet on it,
    /// so UI tests can walk through an import of an assessment already on the device.
    private func presentSampleImport() {
        guard let assessment = currentAssessment else { return }
        Task {
            guard let url = try? await BackupService(context: context).makeBackup(of: [assessment], password: UITestSeed.importPassword)
            else { return }
            // Remove two answers locally, as if a teammate had answered them, so the merge has something to bring in.
            for response in assessment.responses.sorted(by: { $0.requirementID < $1.requirementID }).prefix(2) {
                context.delete(response)
            }
            try? context.save()
            importer.file = url
        }
    }
    #endif
}

// MARK: - Shared pieces

/// The framework rows for the current assessment, with progress.
struct EnabledFrameworkRow: View {
    let entry: FrameworkIndexEntry
    let progress: ProgressSummary

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.shortName).font(.dsHeadline).foregroundStyle(Color.dsTextPrimary)
                Spacer(minLength: DS.Space.xs)
                Text("\(progress.implemented) of \(progress.applicable)")
                    .font(.dsFootnote.monospacedDigit())
                    .foregroundStyle(Color.dsTextSecondary)
            }
            ProgressBar(fraction: progress.fractionImplemented, tint: progress.isComplete ? .dsImplemented : .dsAccent)
        }
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.shortName), \(progress.implemented) of \(progress.applicable) implemented")
    }
}

extension Assessment {
    /// Progress for the requirements in scope for one framework.
    @MainActor
    func progress(for framework: Framework) -> ProgressSummary {
        let scope = scope(for: framework.id)
        let ids = framework.requirementsInScope(scope).map(\.id)
        return ProgressSummary(ids: ids, statuses: statusMap(frameworkID: framework.id))
    }
}

/// Switches assessments and creates new ones.
struct AssessmentSwitcherMenu: View {
    let current: Assessment?
    @Binding var showingNewAssessment: Bool
    let select: (Assessment) -> Void
    @Query(sort: \Assessment.createdAt) private var assessments: [Assessment]

    var body: some View {
        Menu {
            Section("Assessments") {
                ForEach(assessments) { a in
                    Button {
                        select(a)
                    } label: {
                        if a.id == current?.id {
                            Label(a.name, systemImage: "checkmark")
                        } else {
                            Text(a.name)
                        }
                    }
                }
            }
            Button {
                showingNewAssessment = true
            } label: {
                Label("New Assessment", systemImage: "plus")
            }
            ImportAssessmentButton()
        } label: {
            HStack(spacing: DS.Space.xxs) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(current?.name ?? "No assessment")
                        .font(.dsHeadline)
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineLimit(1)
                    if let org = current?.organization, !org.isEmpty {
                        Text(org).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary).lineLimit(1)
                    }
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.dsFootnote.weight(.semibold))
                    .foregroundStyle(Color.dsTextSecondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Current assessment: \(current?.name ?? "none"). Switch assessment")
        .accessibilityIdentifier("assessmentSwitcher")
    }
}

/// First-run state when no assessment exists.
struct NoAssessmentView: View {
    @Binding var showingNewAssessment: Bool

    var body: some View {
        EmptyStateView(
            title: "Create your first assessment",
            message: "An assessment holds your answers for one organization or one review period. Choose the frameworks you want to work through, then answer one question at a time.",
            systemImage: "checklist"
        ) {
            Button("Create Assessment") { showingNewAssessment = true }
                .buttonStyle(.dsPrimary)
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("createFirstAssessment")
            ImportAssessmentButton(title: "Import from a Teammate or Backup")
                .labelStyle(.titleOnly)
                .buttonStyle(.dsSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.noAssessment")
    }
}
