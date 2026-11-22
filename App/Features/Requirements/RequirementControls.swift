import FrameworkKit
import SwiftUI

/// Four large status buttons. ⌘1–⌘4 select a status from a hardware keyboard.
struct StatusPicker: View {
    let selected: RequirementStatus
    let onSelect: (RequirementStatus) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Adaptive so the four options fit side by side only when there is room (for example, a wide
    /// iPad detail column) and wrap to two rows or one column otherwise.
    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize { return [GridItem(.flexible())] }
        let minimum: CGFloat = dynamicTypeSize >= .xxLarge ? 190 : 150
        return [GridItem(.adaptive(minimum: minimum), spacing: DS.Space.xs)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: DS.Space.xs) {
            ForEach(Array(RequirementStatus.allCases.enumerated()), id: \.element) { index, status in
                Button {
                    onSelect(status)
                } label: {
                    StatusOptionLabel(status: status, isSelected: status == selected)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .accessibilityLabel(status.title)
                .accessibilityAddTraits(status == selected ? .isSelected : [])
                .accessibilityHint(status == .notApplicable ? "Asks for a reason" : "")
                .accessibilityIdentifier("status.\(status.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status")
    }
}

private struct StatusOptionLabel: View {
    let status: RequirementStatus
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: isSelected ? status.selectedSymbolName : status.outlineSymbolName)
                .font(.dsBody.weight(.semibold))
            Text(status.title)
                .font(.dsButtonSmall)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? status.color : Color.dsTextSecondary)
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.s)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous)
                .fill(isSelected ? status.color.opacity(0.12) : Color.dsGroupedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous)
                .strokeBorder(isSelected ? status.color : Color.clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
        .hoverEffect(.highlight)
    }
}

extension RequirementStatus {
    /// Unselected options use outline symbols so none of them looks already chosen.
    var outlineSymbolName: String {
        switch self {
        case .notStarted: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .implemented: return "checkmark.circle"
        case .notApplicable: return "minus.circle"
        }
    }

    var selectedSymbolName: String {
        switch self {
        case .notStarted: return "circle.inset.filled"
        case .inProgress: return "circle.lefthalf.filled"
        case .implemented: return "checkmark.circle.fill"
        case .notApplicable: return "minus.circle.fill"
        }
    }
}

/// Asks why a requirement does not apply. A reason is required.
struct NotApplicableReasonSheet: View {
    let initialReason: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @FocusState private var focused: Bool

    private var trimmed: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Reason", text: $reason, prompt: Text("For example: We do not operate any wireless networks."),
                              axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                        .accessibilityIdentifier("naReason")
                } header: {
                    SectionHeader("Why it does not apply")
                } footer: {
                    Text("A reason is required. It appears in reports so reviewers can see why this requirement was excluded.")
                        .font(.dsFootnote)
                }
            }
            .navigationTitle("Not Applicable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                    .accessibilityIdentifier("naSave")
                }
            }
            .onAppear {
                reason = initialReason
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// An organization-defined parameter: free text, or a selection from NIST's choices.
struct ParameterField: View {
    let parameter: Parameter
    let scope: [String: Parameter]
    @Binding var value: String

    private static let separator = "; "

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.dsSubheadline.weight(.semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer(minLength: DS.Space.xs)
                if let label = parameter.displayLabel {
                    Text(label).font(.dsRequirementIDSmall).foregroundStyle(Color.dsTextTertiary)
                        .accessibilityHidden(true)
                }
            }
            if let guidance = Self.readableGuidance(parameter.guidance) {
                Text(guidance)
                    .font(.dsFootnote)
                    .foregroundStyle(Color.dsTextSecondary)
            }
            if parameter.isSelection {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(choices, id: \.self) { choice in
                        Button {
                            toggle(choice)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                                Image(systemName: icon(for: choice))
                                    .foregroundStyle(selectedChoices.contains(choice) ? Color.dsAccent : Color.dsTextTertiary)
                                Text(choice)
                                    .font(.dsBody)
                                    .foregroundStyle(Color.dsTextPrimary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, DS.Space.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedChoices.contains(choice) ? .isSelected : [])
                    }
                }
                Text(parameter.allowsMultipleSelection ? "Select one or more." : "Select one.")
                    .font(.dsFootnote)
                    .foregroundStyle(Color.dsTextTertiary)
            } else {
                TextField("Your value", text: $value, axis: .vertical)
                    .font(.dsBody)
                    .lineLimit(1...4)
                    .padding(.horizontal, DS.Space.s)
                    .padding(.vertical, DS.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Corner.small, style: .continuous)
                            .fill(Color.dsGroupedBackground)
                    )
            }
        }
        .padding(.vertical, DS.Space.xxs)
    }

    /// NIST phrases parameter guidance as an assessment determination ("the time period … is defined;").
    /// Shown as a plain description: "The time period …".
    static func readableGuidance(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        for suffix in [" is/are defined;", " is/are defined.", " is defined;", " is defined.", " are defined;", " are defined.",
                       " is/are selected;", " is/are selected.", " is selected;", " is selected."] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
            break
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ";. "))
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    private var title: String {
        let base = parameter.label ?? parameter.usage ?? "Selection"
        return base.prefix(1).uppercased() + base.dropFirst()
    }

    private var choices: [String] {
        parameter.choices.map { ParameterText.plain($0, parameters: scope, values: [:]) }
    }

    private var selectedChoices: [String] {
        value.isEmpty ? [] : value.components(separatedBy: Self.separator)
    }

    private func icon(for choice: String) -> String {
        let on = selectedChoices.contains(choice)
        if parameter.allowsMultipleSelection { return on ? "checkmark.square.fill" : "square" }
        return on ? "largecircle.fill.circle" : "circle"
    }

    private func toggle(_ choice: String) {
        var current = selectedChoices
        if parameter.allowsMultipleSelection {
            if let i = current.firstIndex(of: choice) { current.remove(at: i) } else { current.append(choice) }
            // Keep NIST's order.
            current = choices.filter(current.contains)
        } else {
            current = current == [choice] ? [] : [choice]
        }
        value = current.joined(separator: Self.separator)
    }
}

/// Statement or objective text with parameter values filled in.
struct TextItemsView: View {
    let items: [TextItem]
    let scope: [String: Parameter]
    let values: [String: String]
    var depth = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    if item.text != nil || item.label != nil {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                            if let label = item.label {
                                Text(label)
                                    .font(.dsRequirementIDSmall)
                                    .foregroundStyle(Color.dsTextSecondary)
                                    .frame(minWidth: 24, alignment: .leading)
                            }
                            if let text = item.text {
                                Text(attributed(text))
                                    .font(.dsBody)
                                    .foregroundStyle(Color.dsTextPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !item.items.isEmpty {
                        TextItemsView(items: item.items, scope: scope, values: values, depth: depth + 1)
                            .padding(.leading, DS.Space.m)
                    }
                }
            }
        }
    }

    private func attributed(_ text: String) -> AttributedString {
        var out = AttributedString()
        for segment in ParameterText.segments(in: text, parameters: scope, values: values) {
            switch segment {
            case .text(let s):
                out += AttributedString(s)
            case .parameter(_, let placeholder, let value):
                if let value {
                    var run = AttributedString(value)
                    run.swiftUI.foregroundColor = .dsAccent
                    run.swiftUI.font = .dsBody.weight(.semibold)
                    out += run
                } else {
                    var run = AttributedString("[\(placeholder)]")
                    run.swiftUI.foregroundColor = .dsTextSecondary
                    run.swiftUI.font = .dsBody.italic()
                    out += run
                }
            }
        }
        return out
    }
}
