import Charts
import FrameworkKit
import SwiftData
import SwiftUI

/// Assessment dashboard: progress per framework and group, CSF Current vs Target, SP 800-53B
/// baseline coverage, and the top next steps.
struct OverviewView: View {
    @Bindable var assessment: Assessment
    var selection: Binding<AppRoute?>?
    @Environment(ContentLibrary.self) private var library

    private var frameworks: [Framework] {
        assessment.enabledFrameworkIDs.compactMap(library.framework)
    }

    var body: some View {
        Group {
            if frameworks.isEmpty {
                EmptyStateView(title: "No frameworks turned on",
                               message: "Turn on at least one framework in Explore Frameworks to see progress here.",
                               systemImage: "chart.bar")
            } else if let selection {
                List(selection: selection) { content }
            } else {
                List { content }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Overview")
        .accessibilityIdentifier("screen.overview")
    }

    @ViewBuilder
    private var content: some View {
        ForEach(frameworks) { fw in
            let statuses = assessment.statusMap(frameworkID: fw.id)
            let scope = assessment.scope(for: fw.id)
            let progress = ProgressSummary(ids: fw.requirementsInScope(scope).map(\.id), statuses: statuses)
            Section {
                NavigationLink(value: AppRoute.requirements(frameworkID: fw.id)) {
                    FrameworkProgressHeader(framework: fw, scopeText: ScopeDescription.short(scope, framework: fw), progress: progress)
                }
                GroupProgressChart(framework: fw, groups: fw.progressByTopGroup(scope: scope, statuses: statuses))
                if !fw.document.tiers.isEmpty {
                    ProfileChart(summaries: ProfileAnalysis.summarize(fw, facts: assessment.factsMap(frameworkID: fw.id)))
                    NavigationLink(value: AppRoute.csfProfile(frameworkID: fw.id)) {
                        Label("Profiles and Tiers", systemImage: "scope")
                    }
                }
                if fw.hasBaselines {
                    BaselineCoverageChart(framework: fw, scope: scope, rows: fw.progressByBaseline(statuses: statuses))
                }
            } header: {
                SectionHeader(fw.document.shortName)
            }
        }

        let steps = NextStepsEngine.rank(frameworks: frameworks, scopes: assessment.scopes,
                                         facts: assessment.allFacts(), graph: library.mappingGraph)
        Section {
            if steps.isEmpty {
                Label("Every requirement in scope has been addressed.", systemImage: "checkmark.seal")
                    .font(.dsCallout)
                    .foregroundStyle(Color.dsImplemented)
            }
            ForEach(steps.prefix(5)) { step in
                if let fw = library.framework(step.ref.frameworkID), let r = fw.requirement(step.ref.requirementID) {
                    NavigationLink(value: AppRoute.requirement(frameworkID: fw.id, requirementID: r.id)) {
                        NextStepRow(step: step, framework: fw, requirement: r)
                    }
                }
            }
            if steps.count > 5 {
                NavigationLink(value: AppRoute.nextSteps) {
                    Text("All \(steps.count) next steps").font(.dsBody)
                }
            }
        } header: {
            SectionHeader("What to do next")
        }
    }
}

// MARK: - Components

/// Percentage, status breakdown bar, and counts for one framework.
struct FrameworkProgressHeader: View {
    let framework: Framework
    let scopeText: String
    let progress: ProgressSummary

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int((progress.fractionImplemented * 100).rounded()))%")
                    .font(.dsTitle)
                    .foregroundStyle(Color.dsTextPrimary)
                    .dsDisplayTypeCap()
                Text("implemented").font(.dsCallout).foregroundStyle(Color.dsTextSecondary)
                Spacer()
                if framework.hasBaselines {
                    Text(scopeText).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                }
            }
            StatusBreakdownBar(progress: progress)
            StatusLegend(progress: progress)
        }
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(framework.document.shortName): \(Int((progress.fractionImplemented * 100).rounded())) percent implemented. \(progress.implemented) implemented, \(progress.inProgress) in progress, \(progress.notStarted) not started, \(progress.notApplicable) not applicable.")
    }
}

/// A single horizontal bar split by status.
struct StatusBreakdownBar: View {
    let progress: ProgressSummary

    private var segments: [(status: RequirementStatus, count: Int)] {
        [RequirementStatus.implemented, .inProgress, .notStarted, .notApplicable].map { ($0, progress.count($0)) }
    }

    var body: some View {
        Chart(segments, id: \.status) { segment in
            BarMark(x: .value("Requirements", segment.count))
                .foregroundStyle(by: .value("Status", segment.status.title))
        }
        .chartForegroundStyleScale(domain: RequirementStatus.chartOrder.map(\.title),
                                   range: RequirementStatus.chartOrder.map(\.chartColor))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...max(progress.total, 1))
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.small / 2, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct StatusLegend: View {
    let progress: ProgressSummary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.m) { items }
            VStack(alignment: .leading, spacing: DS.Space.xxs) { items }
        }
        .font(.dsFootnote.monospacedDigit())
    }

    @ViewBuilder
    private var items: some View {
        ForEach(RequirementStatus.chartOrder) { s in
            HStack(spacing: DS.Space.xxs) {
                Image(systemName: s.symbolName).foregroundStyle(s.chartColor)
                Text("\(progress.count(s)) \(s.title.lowercased())").foregroundStyle(Color.dsTextSecondary)
            }
        }
    }
}

extension RequirementStatus {
    static let chartOrder: [RequirementStatus] = [.implemented, .inProgress, .notStarted, .notApplicable]

    /// Chart fills: status colors, with not started drawn as a light neutral track.
    var chartColor: Color {
        switch self {
        case .notStarted: return Color.dsNotStarted.opacity(0.25)
        default: return color
        }
    }
}

/// Implemented share per CSF Function or control family.
struct GroupProgressChart: View {
    let framework: Framework
    let groups: [GroupProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("By \(framework.document.groupLevels.first?.singular.lowercased() ?? "group")")
                .font(.dsSubheadline.weight(.semibold))
                .foregroundStyle(Color.dsTextPrimary)
            Chart(groups) { item in
                BarMark(x: .value("Implemented", item.progress.fractionImplemented * 100),
                        y: .value(framework.document.groupLevels.first?.singular ?? "Group", item.group.displayId))
                    .foregroundStyle(item.progress.isComplete ? Color.dsImplemented : Color.dsAccent)
                    .annotation(position: .trailing, spacing: DS.Space.xxs) {
                        Text("\(item.progress.implemented)/\(item.progress.applicable)")
                            .font(.dsCaption.monospacedDigit())
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                    .accessibilityLabel("\(item.group.displayId) \(item.group.title)")
                    .accessibilityValue("\(item.progress.implemented) of \(item.progress.applicable) implemented")
            }
            .chartXScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.dsCaption) }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.dsRequirementIDSmall)
                }
            }
            .frame(height: CGFloat(max(groups.count, 1)) * 26 + 30)
        }
        .padding(.vertical, DS.Space.xs)
    }
}

/// CSF Current vs Target per Function.
struct ProfileChart: View {
    let summaries: [ProfileGroupSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Current vs Target").font(.dsSubheadline.weight(.semibold)).foregroundStyle(Color.dsTextPrimary)
            Chart {
                ForEach(summaries) { s in
                    BarMark(x: .value("Outcomes", s.targeted), y: .value("Function", s.groupID))
                        .foregroundStyle(by: .value("Profile", "Target"))
                        .position(by: .value("Profile", "Target"))
                    BarMark(x: .value("Outcomes", s.achieved), y: .value("Function", s.groupID))
                        .foregroundStyle(by: .value("Profile", "Current"))
                        .position(by: .value("Profile", "Current"))
                }
            }
            .chartForegroundStyleScale(["Target": Color.dsAccent.opacity(0.3), "Current": Color.dsAccent])
            .chartLegend(position: .top, alignment: .leading)
            .chartYAxis { AxisMarks { _ in AxisValueLabel().font(.dsRequirementIDSmall) } }
            .frame(height: CGFloat(summaries.count) * 34 + 50)
            .accessibilityElement(children: .contain)
            Text("Current counts targeted outcomes that are implemented. Set the Target Profile in Profiles and Tiers.")
                .font(.dsFootnote)
                .foregroundStyle(Color.dsTextSecondary)
        }
        .padding(.vertical, DS.Space.xs)
    }
}

/// Implemented share of each SP 800-53B baseline, with the selected baseline marked.
struct BaselineCoverageChart: View {
    let framework: Framework
    let scope: ScopeSelection
    let rows: [(baseline: Baseline, progress: ProgressSummary)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Baseline coverage").font(.dsSubheadline.weight(.semibold)).foregroundStyle(Color.dsTextPrimary)
            Chart(rows, id: \.baseline.id) { row in
                BarMark(x: .value("Implemented", row.progress.fractionImplemented * 100),
                        y: .value("Baseline", row.baseline.title))
                    .foregroundStyle(isSelected(row.baseline) ? Color.dsAccent : Color.dsAccent.opacity(0.35))
                    .annotation(position: .trailing, spacing: DS.Space.xxs) {
                        Text("\(row.progress.implemented)/\(row.progress.applicable)")
                            .font(.dsCaption.monospacedDigit())
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                    .accessibilityValue("\(row.progress.implemented) of \(row.progress.applicable) implemented")
            }
            .chartXScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.dsCaption) }
                }
            }
            .frame(height: CGFloat(rows.count) * 30 + 30)
            Text("Shows progress against every SP 800-53B baseline, whichever one this assessment uses. Darker bars are in scope.")
                .font(.dsFootnote)
                .foregroundStyle(Color.dsTextSecondary)
        }
        .padding(.vertical, DS.Space.xs)
    }

    private func isSelected(_ b: Baseline) -> Bool {
        scope.baselineID == b.id || scope.additiveBaselineIDs.contains(b.id)
    }
}

/// One ranked next step with its reasons.
struct NextStepRow: View {
    let step: NextStep
    let framework: Framework
    let requirement: Requirement

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                Text(framework.document.shortName).font(.dsFootnote.weight(.medium)).foregroundStyle(Color.dsTextSecondary)
                RequirementIDLabel(id: requirement.displayId, size: .small)
                Spacer(minLength: DS.Space.xs)
                Image(systemName: step.status.symbolName).foregroundStyle(step.status.color)
                    .accessibilityLabel(step.status.title)
            }
            Text(requirement.title).font(.dsBody).foregroundStyle(Color.dsTextPrimary).lineLimit(3)
            if !step.reasons.isEmpty {
                Text(step.reasons.map(Self.text).joined(separator: " · "))
                    .font(.dsFootnote)
                    .foregroundStyle(step.reasons.contains(where: Self.isOverdue) ? Color.dsDestructive : Color.dsTextSecondary)
            }
        }
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .combine)
    }

    static func isOverdue(_ r: NextStep.Reason) -> Bool {
        if case .overdue = r { return true }
        return false
    }

    static func text(_ reason: NextStep.Reason) -> String {
        switch reason {
        case .overdue(let d): return "Overdue since \(d.formatted(date: .abbreviated, time: .omitted))"
        case .dueSoon(let d): return "Due \(d.formatted(date: .abbreviated, time: .omitted))"
        case .inProgress: return "In progress"
        case .priority(let p): return "\(p.title) priority"
        case .foundational: return "Foundation for other work"
        case .coversMapped(let n): return "Related to \(n) open requirement\(n == 1 ? "" : "s") in other frameworks"
        }
    }
}

/// Every open requirement across enabled frameworks, in priority order.
struct NextStepsView: View {
    @Bindable var assessment: Assessment
    var selection: Binding<AppRoute?>?
    @Environment(ContentLibrary.self) private var library
    @State private var frameworkFilter: String?

    var body: some View {
        let frameworks = assessment.enabledFrameworkIDs.compactMap(library.framework)
        let steps = NextStepsEngine.rank(frameworks: frameworks, scopes: assessment.scopes,
                                         facts: assessment.allFacts(), graph: library.mappingGraph)
            .filter { frameworkFilter == nil || $0.ref.frameworkID == frameworkFilter }
        Group {
            if steps.isEmpty {
                EmptyStateView(title: frameworks.isEmpty ? "No frameworks turned on" : "Nothing open",
                               message: frameworks.isEmpty
                                   ? "Turn on a framework to get a prioritized list of what to do next."
                                   : "Every requirement in scope is implemented or not applicable.",
                               systemImage: "checkmark.seal")
            } else if let selection {
                List(selection: selection) { rows(steps) }
            } else {
                List { rows(steps) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Next Steps")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Framework", selection: $frameworkFilter) {
                        Text("All Frameworks").tag(String?.none)
                        ForEach(frameworks) { fw in Text(fw.document.shortName).tag(Optional(fw.id)) }
                    }
                } label: {
                    Label("Filter", systemImage: frameworkFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .accessibilityIdentifier("screen.nextSteps")
    }

    @ViewBuilder
    private func rows(_ steps: [NextStep]) -> some View {
        Section {
            ForEach(steps) { step in
                if let fw = library.framework(step.ref.frameworkID), let r = fw.requirement(step.ref.requirementID) {
                    NavigationLink(value: AppRoute.requirement(frameworkID: fw.id, requirementID: r.id)) {
                        NextStepRow(step: step, framework: fw, requirement: r)
                    }
                }
            }
        } header: {
            SectionHeader("\(steps.count) open")
        } footer: {
            Text("Ordered by overdue target dates, work in progress, your CSF priorities, foundational policies, and how many related requirements in other frameworks the same work supports.")
                .font(.dsFootnote)
        }
    }
}
