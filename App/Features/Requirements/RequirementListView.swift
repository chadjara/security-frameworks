import FrameworkKit
import SwiftData
import SwiftUI

/// All requirements of one framework for an assessment, grouped by category or family, with
/// search, filters, and quick status actions.
struct RequirementListView: View {
    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case open = "Open"
        case notStarted = "Not Started"
        case inProgress = "In Progress"
        case implemented = "Implemented"
        case notApplicable = "Not Applicable"
        var id: String { rawValue }

        func matches(_ status: RequirementStatus) -> Bool {
            switch self {
            case .all: return true
            case .open: return status == .notStarted || status == .inProgress
            case .notStarted: return status == .notStarted
            case .inProgress: return status == .inProgress
            case .implemented: return status == .implemented
            case .notApplicable: return status == .notApplicable
            }
        }
    }

    @Bindable var assessment: Assessment
    let framework: Framework
    /// Split view selection; `nil` in stack navigation.
    var selection: Binding<AppRoute?>?

    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @State private var searchText = ""
    @State private var searchHits: [String]?
    @State private var statusFilter: StatusFilter = .all
    @State private var showOutOfScope = false
    @State private var questionnaireStart: QuestionnaireStart?
    @State private var reasonRequest: RequirementRef?
    @FocusState private var searchFocused: Bool

    var body: some View {
        let statuses = assessment.statusMap(frameworkID: framework.id)
        let scope = assessment.scope(for: framework.id)
        let inScope = Set(framework.requirementsInScope(scope).map(\.id))
        let progress = ProgressSummary(ids: inScope, statuses: statuses)

        Group {
            if let selection {
                List(selection: selection) { rows(statuses: statuses, inScope: inScope, progress: progress) }
            } else {
                List { rows(statuses: statuses, inScope: inScope, progress: progress) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(framework.document.shortName)
        .searchable(text: $searchText, prompt: "Search by ID or keyword")
        .modifier(SearchFocus(focused: $searchFocused))
        .background {
            // ⌘F focuses search from a hardware keyboard (iOS 18 and later).
            Button("Search") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .task(id: searchText) { await runSearch() }
        .toolbar { toolbar }
        .fullScreenCover(item: $questionnaireStart) { start in
            QuestionnaireView(assessment: assessment, framework: framework, startAt: start.requirementID)
        }
        .sheet(item: $reasonRequest) { ref in
            NotApplicableReasonSheet(initialReason: assessment.response(for: ref)?.notApplicableReason ?? "") { reason in
                AssessmentService(context: context).setStatus(.notApplicable, for: ref, in: assessment, reason: reason)
            }
        }
        .accessibilityIdentifier("screen.requirements")
        .onAppear(perform: openQuestionnaireForUITests)
    }

    // MARK: Rows

    @ViewBuilder
    private func rows(statuses: [String: RequirementStatus], inScope: Set<String>, progress: ProgressSummary) -> some View {
        if searchText.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int((progress.fractionImplemented * 100).rounded()))%")
                            .font(.dsTitle)
                            .foregroundStyle(Color.dsTextPrimary)
                        Text("implemented")
                            .font(.dsCallout)
                            .foregroundStyle(Color.dsTextSecondary)
                        Spacer()
                    }
                    ProgressBar(fraction: progress.fractionImplemented)
                    Text(summaryLine(progress))
                        .font(.dsFootnote)
                        .foregroundStyle(Color.dsTextSecondary)
                    Button {
                        questionnaireStart = QuestionnaireStart(requirementID: nil)
                    } label: {
                        // Wraps to two lines in narrow iPad columns rather than truncating.
                        Label(progress.answered == 0 ? "Start Guided Questions" : "Continue Guided Questions",
                              systemImage: "arrow.forward.circle")
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                    .disabled(progress.total == 0)
                    .padding(.top, DS.Space.xxs)
                    .accessibilityIdentifier("startQuestionnaire")
                }
                .padding(.vertical, DS.Space.xs)
                .accessibilityElement(children: .contain)
            }
        }

        if let hits = searchHits, !searchText.isEmpty {
            let visible = hits.compactMap(framework.requirement).filter { r in
                (showOutOfScope || inScope.contains(r.id)) && statusFilter.matches(statuses[r.id] ?? .notStarted)
            }
            if visible.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(visible) { r in row(r, status: statuses[r.id] ?? .notStarted, inScope: inScope.contains(r.id)) }
                } header: {
                    SectionHeader("\(visible.count) result\(visible.count == 1 ? "" : "s")")
                }
            }
        } else {
            let groups = framework.leafGroups
            let anyVisible = groups.contains { g in !visibleRequirements(in: g, statuses: statuses, inScope: inScope).isEmpty }
            if !anyVisible {
                EmptyStateView(title: "No matching requirements",
                               message: "No requirements match the current filter. Change the filter to see more.",
                               systemImage: "line.3.horizontal.decrease.circle") {
                    Button("Show All") { statusFilter = .all }.buttonStyle(.dsSecondary)
                }
                .listRowBackground(Color.clear)
            }
            ForEach(groups) { group in
                let items = visibleRequirements(in: group, statuses: statuses, inScope: inScope)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { r in row(r, status: statuses[r.id] ?? .notStarted, inScope: inScope.contains(r.id)) }
                    } header: {
                        groupHeader(group, statuses: statuses, inScope: inScope)
                    }
                }
            }
        }
    }

    private func visibleRequirements(in group: RequirementGroup, statuses: [String: RequirementStatus],
                                     inScope: Set<String>) -> [Requirement] {
        framework.requirements(inGroup: group.id).filter { r in
            (showOutOfScope || inScope.contains(r.id)) && statusFilter.matches(statuses[r.id] ?? .notStarted)
        }
    }

    private func groupHeader(_ group: RequirementGroup, statuses: [String: RequirementStatus], inScope: Set<String>) -> some View {
        let ids = framework.requirements(inGroup: group.id).map(\.id).filter(inScope.contains)
        let p = ProgressSummary(ids: ids, statuses: statuses)
        let path = (framework.ancestors(ofGroup: group.id).map(\.title) + [group.title]).joined(separator: " · ")
        return HStack(alignment: .firstTextBaseline) {
            Text("\(group.displayId)  \(path)").dsSectionHeaderStyle()
            Spacer(minLength: DS.Space.xs)
            if p.total > 0 {
                if p.isComplete {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.dsImplemented)
                        .accessibilityLabel("Complete")
                }
                Text("\(p.implemented)/\(p.applicable)")
                    .font(.dsFootnote.monospacedDigit())
                    .foregroundStyle(Color.dsTextSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ r: Requirement, status: RequirementStatus, inScope: Bool) -> some View {
        let ref = RequirementRef(frameworkID: framework.id, requirementID: r.id)
        return NavigationLink(value: AppRoute.requirement(frameworkID: framework.id, requirementID: r.id)) {
            RequirementRow(displayID: r.displayId, title: r.title, status: status)
                .padding(.leading, r.parentId == nil ? 0 : DS.Space.s)
                .opacity(inScope ? 1 : 0.6)
        }
        .accessibilityIdentifier("row.\(r.id)")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if status != .implemented {
                Button { set(.implemented, ref) } label: { Label("Implemented", systemImage: "checkmark.circle") }
                    .tint(.dsImplemented)
            }
        }
        .swipeActions(edge: .trailing) {
            if status != .inProgress {
                Button { set(.inProgress, ref) } label: { Label("In Progress", systemImage: "circle.lefthalf.filled") }
                    .tint(.dsInProgress)
            }
        }
        .contextMenu {
            ForEach(RequirementStatus.allCases) { s in
                Button {
                    if s == .notApplicable { reasonRequest = ref } else { set(s, ref) }
                } label: {
                    Label(s == .notApplicable ? "Not Applicable…" : s.title, systemImage: s.symbolName)
                }
                .disabled(s == status)
            }
            Divider()
            Button {
                questionnaireStart = QuestionnaireStart(requirementID: r.id)
            } label: {
                Label("Answer in Guided Mode", systemImage: "arrow.forward.circle")
            }
        }
        .sensoryFeedback(.success, trigger: status) { old, new in new == .implemented && old != .implemented }
    }

    private func set(_ status: RequirementStatus, _ ref: RequirementRef) {
        AssessmentService(context: context).setStatus(status, for: ref, in: assessment)
    }

    private func summaryLine(_ p: ProgressSummary) -> String {
        var parts = ["\(p.implemented) implemented", "\(p.inProgress) in progress", "\(p.notStarted) not started"]
        if p.notApplicable > 0 { parts.append("\(p.notApplicable) not applicable") }
        return parts.joined(separator: " · ")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Status", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                if framework.hasBaselines {
                    Toggle("Include Items Outside Scope", isOn: $showOutOfScope)
                }
            } label: {
                Label("Filter", systemImage: statusFilter == .all && !showOutOfScope
                      ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .accessibilityIdentifier("filterMenu")
        }
        if !framework.document.tiers.isEmpty {
            ToolbarItem(placement: .secondaryAction) {
                if let selection {
                    Button {
                        selection.wrappedValue = .csfProfile(frameworkID: framework.id)
                    } label: {
                        Label("Profiles and Tiers", systemImage: "scope")
                    }
                } else {
                    NavigationLink(value: AppRoute.csfProfile(frameworkID: framework.id)) {
                        Label("Profiles and Tiers", systemImage: "scope")
                    }
                }
            }
        }
        if framework.hasBaselines {
            ToolbarItem(placement: .secondaryAction) {
                if let selection {
                    Button {
                        selection.wrappedValue = .frameworkSettings(frameworkID: framework.id)
                    } label: {
                        Label("Baseline and Scope", systemImage: "slider.horizontal.3")
                    }
                } else {
                    NavigationLink(value: AppRoute.frameworkSettings(frameworkID: framework.id)) {
                        Label("Baseline and Scope", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
    }

    // MARK: Search

    private func runSearch() async {
        let query = searchText
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchHits = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled, let index = await library.searchIndex(for: framework.id) else { return }
        let hits = index.search(query).map(\.requirementID)
        if !Task.isCancelled { searchHits = hits }
    }

    private func openQuestionnaireForUITests() {
        #if DEBUG
        if case .questionnaire(let fw)? = UITestRoute.current, fw == framework.id, questionnaireStart == nil {
            questionnaireStart = QuestionnaireStart(requirementID: nil)
        }
        #endif
    }
}

/// Binds search field focus where the API exists (iOS 18+).
struct SearchFocus: ViewModifier {
    var focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.searchFocused(focused)
        } else {
            content
        }
    }
}

struct QuestionnaireStart: Identifiable {
    let id = UUID()
    let requirementID: String?
}

extension RequirementRef: @retroactive Identifiable {
    public var id: String { "\(frameworkID)|\(requirementID)" }
}
