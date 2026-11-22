import FrameworkKit
import SwiftData
import SwiftUI

/// Guided mode: one requirement at a time, moving through the requirements in scope.
/// ⌘] and ⌘[ move forward and back from a hardware keyboard.
struct QuestionnaireView: View {
    @Bindable var assessment: Assessment
    let framework: Framework
    let startAt: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var orderedIDs: [String] = []
    @State private var index = 0
    @State private var movingForward = true
    @State private var finished = false

    var body: some View {
        NavigationStack {
            Group {
                if orderedIDs.isEmpty {
                    EmptyStateView(title: "Nothing in scope",
                                   message: "This framework has no requirements in scope for this assessment. Check its baseline and scope settings.",
                                   systemImage: "tray")
                } else if finished {
                    completion
                } else {
                    RequirementDetailView(assessment: assessment, framework: framework,
                                          requirementID: orderedIDs[index], mode: .guided)
                        .id(orderedIDs[index])
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: movingForward ? .trailing : .leading),
                            removal: .move(edge: movingForward ? .leading : .trailing)))
                }
            }
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: prepare)
        .accessibilityIdentifier("screen.questionnaire")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        ToolbarItem(placement: .principal) {
            if !orderedIDs.isEmpty && !finished {
                VStack(spacing: 2) {
                    Text(framework.document.shortName).font(.dsHeadline)
                    Text("\(index + 1) of \(orderedIDs.count) · \(remaining) unanswered")
                        .font(.dsFootnote.monospacedDigit())
                        .foregroundStyle(Color.dsTextSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            if !orderedIDs.isEmpty && !finished {
                Button {
                    move(to: index - 1, forward: false)
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(index == 0)
                .keyboardShortcut("[", modifiers: .command)

                Spacer()

                Button {
                    move(to: index + 1, forward: true)
                } label: {
                    Text("Skip").font(.dsButtonSmall)
                }
                .disabled(index >= orderedIDs.count - 1)
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .accessibilityHint("Moves to the next requirement without changing this one")

                Button {
                    nextUnanswered()
                } label: {
                    HStack(spacing: DS.Space.xxs) {
                        Text("Next").font(.dsButtonSmall)
                        Image(systemName: "chevron.right")
                    }
                }
                .keyboardShortcut("]", modifiers: .command)
                .accessibilityLabel("Next unanswered requirement")
                .accessibilityIdentifier("questionnaireNext")
            }
        }
    }

    // MARK: Completion

    private var completion: some View {
        let p = ProgressSummary(ids: orderedIDs, statuses: assessment.statusMap(frameworkID: framework.id))
        return EmptyStateView(
            title: "Every question is answered",
            message: "All \(p.total) requirements in scope have a status: \(p.implemented) implemented, \(p.inProgress) in progress, and \(p.notApplicable) not applicable. Requirements in progress still need work; you can return to them at any time.",
            systemImage: "checkmark.seal"
        ) {
            Button("Review from the Start") {
                finished = false
                move(to: 0, forward: false)
            }
            .buttonStyle(.dsSecondary)
            Button("Done") { dismiss() }.buttonStyle(.dsPrimary)
        }
    }

    // MARK: Navigation

    private var statuses: [String: RequirementStatus] { assessment.statusMap(frameworkID: framework.id) }
    private var remaining: Int { orderedIDs.filter { (statuses[$0] ?? .notStarted) == .notStarted }.count }

    private func prepare() {
        guard orderedIDs.isEmpty else { return }
        orderedIDs = framework.requirementsInScope(assessment.scope(for: framework.id)).map(\.id)
        let current = statuses
        if let start = startAt, let i = orderedIDs.firstIndex(of: start) {
            index = i
        } else {
            index = orderedIDs.firstIndex { (current[$0] ?? .notStarted) == .notStarted } ?? 0
        }
    }

    private func move(to newIndex: Int, forward: Bool) {
        guard orderedIDs.indices.contains(newIndex) else { return }
        movingForward = forward
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { index = newIndex }
    }

    /// Next not-started requirement after the current one, wrapping around; finishes when none remain.
    private func nextUnanswered() {
        let current = statuses
        let n = orderedIDs.count
        for step in 1...n {
            let i = (index + step) % n
            if (current[orderedIDs[i]] ?? .notStarted) == .notStarted {
                move(to: i, forward: i > index)
                return
            }
        }
        withAnimation(reduceMotion ? nil : .easeInOut) { finished = true }
    }
}
