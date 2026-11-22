import FrameworkKit
import SwiftData
import SwiftUI

/// One requirement: the plain-language question, status, ownership, organization-defined values,
/// evidence, guidance, and NIST's own text.
struct RequirementDetailView: View {
    enum Mode { case standard, guided }

    @Bindable var assessment: Assessment
    let framework: Framework
    let requirementID: String
    var mode: Mode = .standard

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingReasonSheet = false
    @State private var implementedTrigger = 0
    @State private var groupCompleteTrigger = 0
    @State private var groupCompleteMessage: String?
    @State private var showNISTText = false
    @State private var showObjectives = false
    @State private var isDropTargeted = false

    private var service: AssessmentService { AssessmentService(context: context) }

    var body: some View {
        if let requirement = framework.requirement(requirementID) {
            content(requirement)
        } else {
            ErrorStateView(title: "Requirement not found",
                           message: "This requirement is not part of the installed framework content.")
        }
    }

    private func content(_ r: Requirement) -> some View {
        let ref = RequirementRef(frameworkID: framework.id, requirementID: r.id)
        let response = assessment.response(for: ref)
        let status = response?.status ?? .notStarted
        let scope = framework.parameterScope(for: r)
        let values = assessment.parameterValueMap(frameworkID: framework.id)
        let inScope = framework.isInScope(r, selection: assessment.scope(for: framework.id))

        return List {
            Section {
                header(r, inScope: inScope)
                StatusPicker(selected: status) { select($0, ref: ref, requirement: r) }
                    .listRowSeparator(.hidden)
                if let message = groupCompleteMessage {
                    Label(message, systemImage: "checkmark.seal")
                        .font(.dsCallout)
                        .foregroundStyle(Color.dsImplemented)
                        .transition(.opacity)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if let from = response?.appliedFromRequirementID, let fw = response?.appliedFromFrameworkID {
                    Text("Answer applied from \(fw) \(from).")
                        .font(.dsFootnote)
                        .foregroundStyle(Color.dsTextSecondary)
                }
            }

            if status == .notApplicable {
                Section {
                    TextField("Reason", text: binding(ref, \.notApplicableReason), axis: .vertical)
                        .lineLimit(2...6)
                    if (response?.notApplicableReason ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                        Label("A reason is required for requirements marked not applicable.", systemImage: "exclamationmark.circle")
                            .font(.dsFootnote)
                            .foregroundStyle(Color.dsDestructive)
                    }
                } header: {
                    SectionHeader("Why it does not apply")
                }
            }

            if let editorial = r.editorial, status != .implemented, status != .notApplicable {
                Section {
                    ForEach(Array(editorial.nextSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                            Text("\(index + 1)")
                                .font(.dsSubheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.dsAccent)
                                .frame(minWidth: 16, alignment: .leading)
                            Text(step).font(.dsBody).foregroundStyle(Color.dsTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    SectionHeader("Suggested next steps")
                }
            }

            Section {
                LabeledTextField(title: "Owner", prompt: "Person or team responsible", text: binding(ref, \.owner))
                TargetDateRow(date: Binding(
                    get: { response?.targetDate },
                    set: { new in service.update(ref, in: assessment) { $0.targetDate = new } }
                ))
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Notes").font(.dsSubheadline.weight(.semibold)).foregroundStyle(Color.dsTextPrimary)
                    TextField("What your organization does today, gaps, and decisions", text: binding(ref, \.notes),
                              axis: .vertical)
                        .font(.dsBody)
                        .lineLimit(3...12)
                        .accessibilityIdentifier("notes")
                }
                .padding(.vertical, DS.Space.xxs)
            } header: {
                SectionHeader("Ownership and notes")
            }

            let editable = editableParameters(for: r)
            if !editable.isEmpty {
                Section {
                    ForEach(editable) { p in
                        ParameterField(parameter: p, scope: scope, value: Binding(
                            get: { values[p.id] ?? "" },
                            set: { service.setParameter(p.id, frameworkID: framework.id, value: $0, in: assessment) }
                        ))
                    }
                } header: {
                    SectionHeader("Organization-defined values")
                } footer: {
                    Text("NIST leaves these values for your organization to decide. They appear in the requirement text and in reports.")
                        .font(.dsFootnote)
                }
            }

            EvidenceSection(assessment: assessment, ref: ref)

            if let editorial = r.editorial {
                Section {
                    Text(editorial.whyItMatters).font(.dsBody).foregroundStyle(Color.dsTextPrimary)
                } header: {
                    SectionHeader("Why it matters")
                }
                Section {
                    Text(editorial.doneLooksLike).font(.dsBody).foregroundStyle(Color.dsTextPrimary)
                } header: {
                    SectionHeader("What done looks like")
                }
            }

            nistSection(r, scope: scope, values: values)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(r.displayId)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReasonSheet) {
            NotApplicableReasonSheet(initialReason: response?.notApplicableReason ?? "") { reason in
                service.setStatus(.notApplicable, for: ref, in: assessment, reason: reason)
            }
        }
        .dropDestination(for: EvidenceDropFile.self) { files, _ in
            var added = 0
            for file in files {
                if let stored = try? EvidenceFileStore.importFile(at: file.url, assessmentID: assessment.id) {
                    service.addFile(stored, to: ref, in: assessment)
                    added += 1
                }
            }
            return added > 0
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous)
                    .strokeBorder(Color.dsAccent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .overlay(alignment: .bottom) {
                        Label("Drop to add as evidence", systemImage: "arrow.down.doc")
                            .font(.dsHeadline)
                            .foregroundStyle(Color.dsOnAccent)
                            .padding(.horizontal, DS.Space.m)
                            .padding(.vertical, DS.Space.s)
                            .background(Capsule().fill(Color.dsAccent))
                            .padding(DS.Space.l)
                    }
                    .padding(DS.Space.xs)
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.success, trigger: implementedTrigger)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: groupCompleteTrigger)
        .sensoryFeedback(.selection, trigger: status)
        .accessibilityIdentifier("screen.requirementDetail")
        .onAppear { showNISTText = r.editorial == nil }
    }

    // MARK: Header

    private func header(_ r: Requirement, inScope: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            let idLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.xxs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            idLayout {
                RequirementIDLabel(id: r.displayId, size: .large)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: DS.Space.xs) }
                Text(framework.kind(r.kind)?.singular ?? "")
                    .font(.dsFootnote)
                    .foregroundStyle(Color.dsTextSecondary)
            }
            Text(r.title)
                .font(.dsTitle2)
                .foregroundStyle(Color.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .dsDisplayTypeCap()
            Text(groupPath(r))
                .font(.dsFootnote)
                .foregroundStyle(Color.dsTextSecondary)
            if framework.hasBaselines {
                Text(baselineLine(r, inScope: inScope))
                    .font(.dsFootnote)
                    .foregroundStyle(Color.dsTextSecondary)
            }
            if let question = r.editorial?.question {
                Text(question)
                    .font(.dsBody.weight(.medium))
                    .foregroundStyle(Color.dsTextPrimary)
                    .padding(.top, DS.Space.xs)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("question")
            } else {
                Text("Has your organization implemented this \(framework.kind(r.kind)?.singular.lowercased() ?? "requirement")? Read NIST's text below to decide.")
                    .font(.dsBody.weight(.medium))
                    .foregroundStyle(Color.dsTextPrimary)
                    .padding(.top, DS.Space.xs)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .combine)
    }

    private func groupPath(_ r: Requirement) -> String {
        guard let group = framework.group(r.groupId) else { return "" }
        var parts = (framework.ancestors(ofGroup: group.id) + [group]).map { "\($0.displayId) \($0.title)" }
        if let parent = r.parentId.flatMap(framework.requirement) {
            parts.append("Enhances \(parent.displayId) \(parent.title)")
        }
        return parts.joined(separator: " › ")
    }

    private func baselineLine(_ r: Requirement, inScope: Bool) -> String {
        let names = r.baselines.compactMap { framework.baseline($0)?.title }
        let baselines = names.isEmpty ? "Not in an SP 800-53B baseline" : "Baselines: " + names.joined(separator: ", ")
        return inScope ? baselines : baselines + " · Outside this assessment's scope"
    }

    /// Own editable parameters plus base-control parameters referenced by this enhancement's text.
    private func editableParameters(for r: Requirement) -> [Parameter] {
        var out = r.editableParameters
        let scope = framework.parameterScope(for: r)
        var seen = Set(out.map(\.id))
        let tokens = r.statement.flatMap(\.flattened).compactMap(\.text).flatMap(ParameterText.tokens(in:))
        for token in tokens {
            guard let p = scope[token] else { continue }
            let targets = p.isAggregate ? p.aggregates.compactMap { scope[$0] } : [p]
            for t in targets where !seen.contains(t.id) {
                out.append(t)
                seen.insert(t.id)
            }
        }
        return out
    }

    // MARK: NIST text

    private func nistSection(_ r: Requirement, scope: [String: Parameter], values: [String: String]) -> some View {
        Section {
            DisclosureGroup(isExpanded: $showNISTText) {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    TextItemsView(items: r.statement, scope: scope, values: values)
                    if let discussion = r.discussion {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("Discussion").font(.dsSectionHeader).textCase(.uppercase).tracking(0.6)
                                .foregroundStyle(Color.dsTextSecondary)
                            Text(discussion).font(.dsBody).foregroundStyle(Color.dsTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !r.examples.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text("Implementation examples").font(.dsSectionHeader).textCase(.uppercase).tracking(0.6)
                                .foregroundStyle(Color.dsTextSecondary)
                            TextItemsView(items: r.examples, scope: scope, values: values)
                        }
                    }
                    if !r.objectives.isEmpty {
                        DisclosureGroup("Assessment objectives (\(r.objectives.flatMap(\.flattened).filter { $0.text != nil }.count))",
                                        isExpanded: $showObjectives) {
                            TextItemsView(items: r.objectives, scope: scope, values: values)
                                .padding(.top, DS.Space.xs)
                        }
                        .font(.dsSubheadline.weight(.semibold))
                    }
                    if !r.references.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("NIST references").font(.dsSectionHeader).textCase(.uppercase).tracking(0.6)
                                .foregroundStyle(Color.dsTextSecondary)
                            ForEach(r.references, id: \.title) { ref in
                                if let s = ref.url, let url = URL(string: s) {
                                    Link(ref.title, destination: url).font(.dsCallout)
                                } else {
                                    Text(ref.title).font(.dsCallout).foregroundStyle(Color.dsTextSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, DS.Space.xs)
            } label: {
                Text("NIST text").font(.dsHeadline).foregroundStyle(Color.dsTextPrimary)
            }
            if let url = URL(string: r.sourceUrl) {
                Link(destination: url) {
                    Label("View on the NIST website", systemImage: "arrow.up.right.square")
                        .font(.dsCallout)
                }
            }
        } header: {
            SectionHeader("Source")
        } footer: {
            Text("\(framework.document.publicationId) · \(framework.document.source.catalogVersion.map { "Release \($0)" } ?? framework.document.version)")
                .font(.dsFootnote)
        }
    }

    // MARK: Actions

    private func select(_ status: RequirementStatus, ref: RequirementRef, requirement r: Requirement) {
        if status == .notApplicable {
            showingReasonSheet = true
            return
        }
        let before = assessment.status(for: ref)
        service.setStatus(status, for: ref, in: assessment)
        guard status == .implemented, before != .implemented else { return }
        implementedTrigger += 1
        checkGroupCompletion(for: r)
    }

    private func checkGroupCompletion(for r: Requirement) {
        guard let group = framework.group(r.groupId) else { return }
        let scope = assessment.scope(for: framework.id)
        let ids = framework.requirements(inGroup: group.id).filter { framework.isInScope($0, selection: scope) }.map(\.id)
        let progress = ProgressSummary(ids: ids, statuses: assessment.statusMap(frameworkID: framework.id))
        guard progress.isComplete else { return }
        groupCompleteTrigger += 1
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            groupCompleteMessage = "Every requirement in \(group.title) is addressed."
        }
    }

    private func binding(_ ref: RequirementRef, _ keyPath: ReferenceWritableKeyPath<RequirementResponse, String>) -> Binding<String> {
        Binding(
            get: { assessment.response(for: ref)?[keyPath: keyPath] ?? "" },
            set: { new in service.update(ref, in: assessment) { $0[keyPath: keyPath] = new } }
        )
    }
}

/// A labeled single-line text field that stacks at accessibility sizes.
struct LabeledTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(title).font(.dsSubheadline.weight(.semibold)).foregroundStyle(Color.dsTextPrimary)
            TextField(prompt, text: $text)
                .font(.dsBody)
                .textContentType(.name)
        }
        .padding(.vertical, DS.Space.xxs)
    }
}

/// Optional target date: off until the user adds one.
struct TargetDateRow: View {
    @Binding var date: Date?

    var body: some View {
        if let value = date {
            HStack {
                DatePicker("Target date", selection: Binding(get: { value }, set: { date = $0 }), displayedComponents: .date)
                    .font(.dsBody)
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.dsTextTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove target date")
            }
        } else {
            Button {
                date = Calendar.current.date(byAdding: .day, value: 30, to: Date())
            } label: {
                Label("Add Target Date", systemImage: "calendar.badge.plus").font(.dsBody)
            }
        }
    }
}
