import FrameworkKit
import SwiftData
import SwiftUI

/// iPhone and narrow windows: tabs with a navigation stack each.
struct CompactRootView: View {
    enum Tab: Hashable { case overview, assessment, nextSteps, explore, settings }

    let assessment: Assessment?
    @Binding var showingNewAssessment: Bool
    let selectAssessment: (Assessment) -> Void

    @State private var tab: Tab = .overview
    @State private var overviewPath: [AppRoute] = []
    @State private var nextStepsPath: [AppRoute] = []
    @State private var assessmentPath: [AppRoute] = []
    @State private var explorePath: [AppRoute] = []
    @State private var settingsPath: [AppRoute] = []
    @State private var didApplyRoute = false

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $overviewPath) {
                Group {
                    if let assessment {
                        OverviewView(assessment: assessment, selection: nil)
                    } else {
                        NoAssessmentView(showingNewAssessment: $showingNewAssessment)
                    }
                }
                .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0, assessment: assessment) }
            }
            .tabItem { Label("Overview", systemImage: "chart.bar.xaxis") }
            .tag(Tab.overview)

            NavigationStack(path: $assessmentPath) {
                AssessmentHomeView(assessment: assessment, showingNewAssessment: $showingNewAssessment,
                                   selectAssessment: selectAssessment)
                    .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0, assessment: assessment) }
            }
            .tabItem { Label("Frameworks", systemImage: "checklist") }
            .tag(Tab.assessment)

            NavigationStack(path: $nextStepsPath) {
                Group {
                    if let assessment {
                        NextStepsView(assessment: assessment, selection: nil)
                    } else {
                        NoAssessmentView(showingNewAssessment: $showingNewAssessment)
                    }
                }
                .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0, assessment: assessment) }
            }
            .tabItem { Label("Next Steps", systemImage: "list.number") }
            .tag(Tab.nextSteps)

            NavigationStack(path: $explorePath) {
                FrameworkExplorerView(assessment: assessment, selection: nil)
                    .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0, assessment: assessment) }
            }
            .tabItem { Label("Explore", systemImage: "books.vertical") }
            .tag(Tab.explore)

            NavigationStack(path: $settingsPath) {
                SettingsView(selection: nil)
                    .navigationDestination(for: AppRoute.self) { RouteDestination(route: $0, assessment: assessment) }
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        .onChange(of: assessment?.id) { _, _ in
            assessmentPath = []
            overviewPath = []
            nextStepsPath = []
        }
        .onAppear(perform: applyRoute)
    }

    private func applyRoute() {
        #if DEBUG
        guard !didApplyRoute else { return }
        didApplyRoute = true
        switch UITestRoute.current {
        case .list(let fw), .questionnaire(let fw): tab = .assessment; assessmentPath = [.requirements(frameworkID: fw)]
        case .detail(let fw, let req):
            tab = .assessment
            assessmentPath = [.requirements(frameworkID: fw), .requirement(frameworkID: fw, requirementID: req)]
        case .home: tab = .assessment
        case .overview, .export: tab = .overview
        case .nextSteps: tab = .nextSteps
        case .profile(let fw): tab = .assessment; assessmentPath = [.requirements(frameworkID: fw), .csfProfile(frameworkID: fw)]
        case .explorer: tab = .explore
        case .preview(let fw): tab = .explore; explorePath = [.frameworkPreview(frameworkID: fw)]
        case .scope(let fw): tab = .explore; explorePath = [.frameworkPreview(frameworkID: fw), .frameworkSettings(frameworkID: fw)]
        case .assessments:
            tab = .assessment
            if let assessment { assessmentPath = [.assessment(assessment.id)] }
        case .settings: tab = .settings
        default: break
        }
        #endif
    }
}

/// The iPhone home tab: current assessment and its frameworks.
struct AssessmentHomeView: View {
    let assessment: Assessment?
    @Binding var showingNewAssessment: Bool
    let selectAssessment: (Assessment) -> Void
    @Environment(ContentLibrary.self) private var library

    var body: some View {
        Group {
            if let assessment {
                List {
                    Section {
                        let enabled = library.entries.filter { assessment.isEnabled($0.id) }
                        if enabled.isEmpty {
                            NoticeView(title: "No frameworks turned on",
                                       message: "Open Explore to choose the frameworks this assessment covers.",
                                       systemImage: "books.vertical")
                        }
                        ForEach(enabled) { entry in
                            if let fw = library.framework(entry.id) {
                                NavigationLink(value: AppRoute.requirements(frameworkID: entry.id)) {
                                    EnabledFrameworkRow(entry: entry, progress: assessment.progress(for: fw))
                                }
                                .accessibilityIdentifier("home.\(entry.id)")
                            }
                        }
                    } header: {
                        SectionHeader("Frameworks")
                    }

                    Section {
                        NavigationLink(value: AppRoute.assessment(assessment.id)) {
                            Label("Assessment Details", systemImage: "info.circle")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .accessibilityIdentifier("screen.home")
            } else {
                NoAssessmentView(showingNewAssessment: $showingNewAssessment)
            }
        }
        .navigationTitle(assessment?.name ?? "Assessments")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AssessmentSwitcherMenu(current: assessment, showingNewAssessment: $showingNewAssessment,
                                       select: selectAssessment)
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewAssessment = true
                } label: {
                    Label("New Assessment", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("newAssessment")
            }
        }
    }
}
