import FrameworkKit
import SwiftUI

/// Shared components in their real contexts: status, rows, notices, progress, and screen states.
struct ComponentGalleryView: View {
    var body: some View {
        List {
            Section {
                ForEach(RequirementStatus.allCases) { status in
                    HStack {
                        StatusBadge(status: status)
                        Spacer()
                        StatusBadge(status: status, style: .tinted)
                    }
                }
            } header: {
                SectionHeader("Status")
            } footer: {
                Text("Each status pairs a color with its own symbol and label, so it never depends on color alone.")
                    .font(.dsFootnote)
            }

            Section {
                RequirementRow(displayID: "GV.OC-01",
                               title: "The organizational mission is understood and informs cybersecurity risk management",
                               status: .implemented)
                RequirementRow(displayID: "AC-2(1)", title: "Automated System Account Management", status: .inProgress)
                RequirementRow(displayID: "03.01.01", title: "Account Management", status: .notStarted)
                RequirementRow(displayID: "PE-3(1)", title: "System Access", status: .notApplicable)
            } header: {
                SectionHeader("Requirement rows")
            }

            Section {
                NoticeView(title: "Confirm the required revision",
                           message: "Organizations with U.S. Department of Defense contracts, including those preparing for CMMC, should confirm which revision of SP 800-171 their contract requires.")
                KeyValueRow(label: "Requirements", value: "97")
                KeyValueRow(label: "Organization-defined parameters", value: "88")
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack {
                        Text("Protect").font(.dsHeadline)
                        Spacer()
                        Text("12 of 32").font(.dsSubheadline.monospacedDigit()).foregroundStyle(Color.dsTextSecondary)
                    }
                    ProgressBar(fraction: 12.0 / 32.0)
                }
                .padding(.vertical, DS.Space.xxs)
                .accessibilityElement(children: .combine)
            } header: {
                SectionHeader("Notices, values, and progress")
            }

            Section {
                EmptyStateView(title: "No assessments yet",
                               message: "Create an assessment for your organization to start answering questions.",
                               systemImage: "checklist") {
                    Button("Create Assessment") {}.buttonStyle(.dsPrimary)
                }
                .frame(minHeight: 260)
            } header: {
                SectionHeader("Empty state")
            }

            Section {
                LoadingStateView(message: "Loading SP 800-53 controls")
                    .frame(minHeight: 120)
            } header: {
                SectionHeader("Loading state")
            }

            Section {
                ErrorStateView(title: "Content could not be loaded",
                               message: "The framework file is damaged or missing. Reinstall the app to restore it.",
                               retry: {})
                    .frame(minHeight: 260)
            } header: {
                SectionHeader("Error state")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Components")
        .accessibilityIdentifier("screen.components")
    }
}
