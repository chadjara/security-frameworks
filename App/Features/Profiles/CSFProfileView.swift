import FrameworkKit
import SwiftData
import SwiftUI

/// CSF Organizational Profiles (Current vs Target) and Tiers.
struct CSFProfileView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case target = "Target Profile"
        case tiers = "Tiers"
        var id: String { rawValue }
    }

    @Bindable var assessment: Assessment
    let framework: Framework
    @Environment(\.modelContext) private var context
    @State private var tab: Tab = CSFProfileView.initialTab

    private var service: AssessmentService { AssessmentService(context: context) }

    /// UI tests open a specific tab with `-uiProfileTab target|tiers` (debug builds only).
    private static var initialTab: Tab {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "uiProfileTab") {
        case "target": return .target
        case "tiers": return .tiers
        default: return .summary
        }
        #else
        return .summary
        #endif
    }

    var body: some View {
        let facts = assessment.factsMap(frameworkID: framework.id)
        List {
            Section {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch tab {
            case .summary: summary(facts)
            case .target: targetProfile(facts)
            case .tiers: tiers
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Profiles and Tiers")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.csfProfile")
    }

    // MARK: Summary

    @ViewBuilder
    private func summary(_ facts: [String: ResponseFacts]) -> some View {
        let summaries = ProfileAnalysis.summarize(framework, facts: facts)
        let targeted = summaries.reduce(0) { $0 + $1.targeted }
        let achieved = summaries.reduce(0) { $0 + $1.achieved }
        Section {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(achieved) of \(targeted)").font(.dsTitle).dsDisplayTypeCap()
                    Text("targeted outcomes achieved").font(.dsCallout).foregroundStyle(Color.dsTextSecondary)
                }
                ProgressBar(fraction: targeted == 0 ? 0 : Double(achieved) / Double(targeted))
                Text(tierSummary).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
            }
            .padding(.vertical, DS.Space.xs)
            ProfileChart(summaries: summaries)
        } footer: {
            Text("Your Current Profile is what you record as implemented. Your Target Profile is the set of outcomes you intend to achieve, with priorities. Outcomes marked not applicable are left out of both.")
                .font(.dsFootnote)
        }

        let gaps = ProfileAnalysis.gaps(framework, facts: facts)
        Section {
            if gaps.isEmpty {
                Label("Every targeted outcome is achieved.", systemImage: "checkmark.seal")
                    .foregroundStyle(Color.dsImplemented)
            }
            ForEach(gaps.prefix(15)) { r in
                NavigationLink(value: AppRoute.requirement(frameworkID: framework.id, requirementID: r.id)) {
                    HStack(alignment: .top) {
                        RequirementRow(displayID: r.displayId, title: r.title, status: facts[r.id]?.status ?? .notStarted)
                        if let p = facts[r.id]?.priority {
                            Text(p.title).font(.dsFootnote.weight(.medium)).foregroundStyle(p == .high ? Color.dsDestructive : Color.dsTextSecondary)
                        }
                    }
                }
            }
            if gaps.count > 15 {
                Text("\(gaps.count - 15) more gaps. Set priorities in Target Profile to bring the most important ones to the top.")
                    .font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
            }
        } header: {
            SectionHeader("Gaps (\(gaps.count))")
        }
    }

    private var tierSummary: String {
        let name = { (n: Int?) -> String in
            guard let n, let t = framework.document.tiers.first(where: { $0.number == n }) else { return "not set" }
            return "Tier \(t.number), \(t.title)"
        }
        return "Current tier: \(name(assessment.csfCurrentTier)) · Target tier: \(name(assessment.csfTargetTier))"
    }

    // MARK: Target Profile

    @ViewBuilder
    private func targetProfile(_ facts: [String: ResponseFacts]) -> some View {
        ForEach(framework.leafGroups) { group in
            Section {
                ForEach(framework.requirements(inGroup: group.id)) { r in
                    TargetRow(requirement: r, facts: facts[r.id] ?? ResponseFacts(),
                              setIncluded: { service.setInTargetProfile($0, for: ref(r), in: assessment) },
                              setPriority: { service.setPriority($0, for: ref(r), in: assessment) })
                }
            } header: {
                SectionHeader("\(group.displayId)  \(group.title)")
            }
        }
    }

    private func ref(_ r: Requirement) -> RequirementRef {
        RequirementRef(frameworkID: framework.id, requirementID: r.id)
    }

    // MARK: Tiers

    @ViewBuilder
    private var tiers: some View {
        Section {
            TierPicker(title: "Current tier", tiers: framework.document.tiers, selection: Binding(
                get: { assessment.csfCurrentTier }, set: { assessment.csfCurrentTier = $0; assessment.touch() }))
            TierPicker(title: "Target tier", tiers: framework.document.tiers, selection: Binding(
                get: { assessment.csfTargetTier }, set: { assessment.csfTargetTier = $0; assessment.touch() }))
        } footer: {
            Text(framework.document.tiersSource?.introduction ?? "")
                .font(.dsFootnote)
        }
        ForEach(framework.document.tiers) { tier in
            Section {
                TierDescription(heading: "Cybersecurity risk governance", lines: tier.governance)
                TierDescription(heading: "Cybersecurity risk management", lines: tier.management)
            } header: {
                HStack {
                    SectionHeader("Tier \(tier.number): \(tier.title)")
                    Spacer()
                    if assessment.csfCurrentTier == tier.number {
                        Text("Current").font(.dsFootnote.weight(.medium)).foregroundStyle(Color.dsAccent)
                    }
                    if assessment.csfTargetTier == tier.number {
                        Text("Target").font(.dsFootnote.weight(.medium)).foregroundStyle(Color.dsImplemented)
                    }
                }
            }
        }
        if let source = framework.document.tiersSource, let url = URL(string: source.url) {
            Section {
                Link(destination: url) {
                    Label("NIST CSWP 29, Appendix B (pages \(source.pages))", systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("Tier descriptions are NIST's notional illustration, quoted from the CSF 2.0 publication. Tiers describe the rigor of your practices; they are not maturity scores or certification levels.")
                    .font(.dsFootnote)
            }
        }
    }
}

private struct TargetRow: View {
    let requirement: Requirement
    let facts: ResponseFacts
    let setIncluded: (Bool) -> Void
    let setPriority: (ProfilePriority?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                RequirementIDLabel(id: requirement.displayId, size: .small)
                Spacer()
                Image(systemName: facts.status.symbolName).foregroundStyle(facts.status.color)
                    .accessibilityLabel("Current: \(facts.status.title)")
            }
            Text(requirement.title).font(.dsBody).foregroundStyle(facts.inTargetProfile ? Color.dsTextPrimary : Color.dsTextTertiary)
            HStack {
                Toggle("In target", isOn: Binding(get: { facts.inTargetProfile }, set: setIncluded))
                    .toggleStyle(.button)
                    .font(.dsFootnote)
                    .tint(.dsAccent)
                Spacer()
                Menu {
                    Picker("Priority", selection: Binding(get: { facts.priority }, set: setPriority)) {
                        Text("No priority").tag(ProfilePriority?.none)
                        ForEach(ProfilePriority.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                } label: {
                    Label(facts.priority.map { "\($0.title) priority" } ?? "Set priority", systemImage: "flag")
                        .font(.dsFootnote)
                }
                .disabled(!facts.inTargetProfile)
            }
        }
        .padding(.vertical, DS.Space.xxs)
    }
}

private struct TierPicker: View {
    let title: String
    let tiers: [Tier]
    @Binding var selection: Int?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Not set").tag(Int?.none)
            ForEach(tiers) { t in Text("Tier \(t.number): \(t.title)").tag(Optional(t.number)) }
        }
        .font(.dsBody)
    }
}

private struct TierDescription: View {
    let heading: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(heading).font(.dsSubheadline.weight(.semibold)).foregroundStyle(Color.dsTextPrimary)
            ForEach(lines, id: \.self) { line in
                Text(line).font(.dsCallout).foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DS.Space.xxs)
    }
}
