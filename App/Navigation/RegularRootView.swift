import FrameworkKit
import SwiftData
import SwiftUI

/// iPad and wide windows: sidebar → list → detail.
struct RegularRootView: View {
    let assessment: Assessment?
    @Binding var showingNewAssessment: Bool
    let selectAssessment: (Assessment) -> Void

    @Environment(ContentLibrary.self) private var library
    @State private var sidebar: SidebarItem?
    @State private var detail: AppRoute?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarList
                .navigationTitle("Assessment")
                .navigationBarTitleDisplayMode(.inline)
        } content: {
            contentColumn
        } detail: {
            NavigationStack {
                detailColumn
                    .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0, assessment: assessment) }
            }
        }
        .onChange(of: sidebar) { _, _ in detail = nil }
        .onAppear(perform: applyInitialSelection)
        .onChange(of: assessment?.id) { _, _ in sidebar = defaultSidebar }
    }

    // MARK: Sidebar

    private var sidebarList: some View {
        List(selection: $sidebar) {
            Section {
                AssessmentSwitcherMenu(current: assessment, showingNewAssessment: $showingNewAssessment,
                                       select: selectAssessment)
                    .padding(.vertical, DS.Space.xxs)
            }

            if assessment != nil {
                Section {
                    Label("Overview", systemImage: "chart.bar.xaxis").tag(SidebarItem.overview)
                        .accessibilityIdentifier("sidebar.overview")
                    Label("Next Steps", systemImage: "list.number").tag(SidebarItem.nextSteps)
                        .accessibilityIdentifier("sidebar.nextSteps")
                }
            }

            if let assessment {
                Section {
                    let enabled = library.entries.filter { assessment.isEnabled($0.id) }
                    if enabled.isEmpty {
                        Text("No frameworks are turned on. Choose one in Explore Frameworks.")
                            .font(.dsFootnote)
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                    ForEach(enabled) { entry in
                        if let fw = library.framework(entry.id) {
                            EnabledFrameworkRow(entry: entry, progress: assessment.progress(for: fw))
                                .tag(SidebarItem.framework(entry.id))
                                .accessibilityIdentifier("sidebar.\(entry.id)")
                        }
                    }
                } header: {
                    SectionHeader("Frameworks")
                }
            }

            Section {
                Label("Explore Frameworks", systemImage: "books.vertical").tag(SidebarItem.explorer)
                Label("Assessments", systemImage: "folder").tag(SidebarItem.assessments)
                Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)
            } header: {
                SectionHeader("Library")
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewAssessment = true
                } label: {
                    Label("New Assessment", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var contentColumn: some View {
        if let assessment {
            switch sidebar {
            case .framework(let id):
                if let fw = library.framework(id) {
                    RequirementListView(assessment: assessment, framework: fw, selection: $detail)
                } else {
                    EmptyStateView(title: "Framework unavailable", message: "This framework is not installed.",
                                   systemImage: "questionmark.folder")
                }
            case .overview:
                OverviewView(assessment: assessment, selection: $detail)
                    .navigationSplitViewColumnWidth(min: 380, ideal: 480, max: 620)
            case .nextSteps:
                NextStepsView(assessment: assessment, selection: $detail)
            case .explorer:
                FrameworkExplorerView(assessment: assessment, selection: $detail)
            case .assessments:
                AssessmentListView(current: assessment, selection: $detail, showingNewAssessment: $showingNewAssessment,
                                   selectAssessment: selectAssessment)
            case .settings:
                SettingsView(selection: $detail)
            case nil:
                EmptyStateView(title: "Choose a section", message: "Select a framework or a section in the sidebar.",
                               systemImage: "sidebar.left")
            }
        } else {
            switch sidebar {
            case .explorer:
                FrameworkExplorerView(assessment: nil, selection: $detail)
            case .settings:
                SettingsView(selection: $detail)
            default:
                NoAssessmentView(showingNewAssessment: $showingNewAssessment)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detailColumn: some View {
        if let detail {
            RouteDestination(route: detail, assessment: assessment)
                .id(detail)
        } else {
            switch sidebar {
            case .framework, .overview, .nextSteps:
                EmptyStateView(title: "Select a requirement",
                               message: "Choose a requirement to record its status, owner, notes, and evidence.",
                               systemImage: "checklist")
            case .explorer:
                EmptyStateView(title: "Select a framework",
                               message: "Preview what a framework covers before you turn it on.",
                               systemImage: "books.vertical")
            default:
                EmptyStateView(title: "Nothing selected", message: "Choose an item from the list.",
                               systemImage: "rectangle.dashed")
            }
        }
    }

    // MARK: Initial state

    private var defaultSidebar: SidebarItem? {
        guard let assessment else { return nil }
        return assessment.enabledFrameworkIDs.isEmpty ? .explorer : .overview
    }

    private func applyInitialSelection() {
        guard sidebar == nil else { return }
        sidebar = defaultSidebar
        #if DEBUG
        switch UITestRoute.current {
        case .list(let fw), .questionnaire(let fw): sidebar = .framework(fw)
        case .detail(let fw, let req):
            sidebar = .framework(fw)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { detail = .requirement(frameworkID: fw, requirementID: req) }
        case .explorer: sidebar = .explorer
        case .preview(let fw):
            sidebar = .explorer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { detail = .frameworkPreview(frameworkID: fw) }
        case .scope(let fw):
            sidebar = .explorer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { detail = .frameworkSettings(frameworkID: fw) }
        case .assessments: sidebar = .assessments
        case .settings: sidebar = .settings
        case .overview: sidebar = .overview
        case .nextSteps: sidebar = .nextSteps
        case .profile(let fw):
            sidebar = .framework(fw)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { detail = .csfProfile(frameworkID: fw) }
        default: break
        }
        #endif
    }
}

/// Renders an `AppRoute` in either navigation style.
struct RouteDestination: View {
    let route: AppRoute
    let assessment: Assessment?
    @Environment(ContentLibrary.self) private var library
    @Query private var assessments: [Assessment]

    var body: some View {
        switch route {
        case .requirements(let id):
            if let assessment, let fw = library.framework(id) {
                RequirementListView(assessment: assessment, framework: fw, selection: nil)
            } else { missing }
        case .requirement(let fid, let rid):
            if let assessment, let fw = library.framework(fid) {
                RequirementDetailView(assessment: assessment, framework: fw, requirementID: rid)
            } else { missing }
        case .frameworkPreview(let id):
            if let entry = library.entry(id), let fw = library.framework(id) {
                FrameworkPreviewView(entry: entry, framework: fw, assessment: assessment)
            } else { missing }
        case .frameworkSettings(let id):
            if let assessment, let fw = library.framework(id) {
                FrameworkScopeView(assessment: assessment, framework: fw)
            } else { missing }
        case .groupPreview(let fid, let gid):
            if let fw = library.framework(fid) {
                GroupPreviewView(framework: fw, groupID: gid)
            } else { missing }
        case .assessment(let id):
            if let a = assessments.first(where: { $0.id == id }) {
                AssessmentDetailView(assessment: a)
            } else { missing }
        case .settings(let page):
            SettingsPageView(page: page)
        case .overview:
            if let assessment { OverviewView(assessment: assessment, selection: nil) } else { missing }
        case .nextSteps:
            if let assessment { NextStepsView(assessment: assessment, selection: nil) } else { missing }
        case .csfProfile(let id):
            if let assessment, let fw = library.framework(id) {
                CSFProfileView(assessment: assessment, framework: fw)
            } else { missing }
        }
    }

    private var missing: some View {
        EmptyStateView(title: "Not available", message: "This item is no longer available.", systemImage: "questionmark.circle")
    }
}
