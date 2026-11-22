import SwiftUI

/// Every text style in the design system, shown with realistic app copy.
struct TypeSpecimenView: View {
    enum PreviewSize: String, CaseIterable, Identifiable {
        case standard = "Default"
        case large = "Large"
        case accessibility = "AX3"
        var id: String { rawValue }
        var dynamicTypeSize: DynamicTypeSize? {
            switch self {
            case .standard: return nil
            case .large: return .xxxLarge
            case .accessibility: return .accessibility3
            }
        }
    }

    @State private var previewSize: PreviewSize = .standard

    var body: some View {
        List {
            Section {
                Picker("Preview text size", selection: $previewSize) {
                    ForEach(PreviewSize.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("specimen.sizePicker")
            } footer: {
                Text("All styles follow the system text size. Use this control to preview larger sizes without changing Settings.")
                    .font(.dsFootnote)
            }

            Group {
                Section {
                    ForEach(Font.specimen) { style in
                        SpecimenRow(style: style, sample: Self.displaySamples[style.id] ?? style.name,
                                    uppercase: style.id == "sectionHeader")
                    }
                } header: {
                    SectionHeader("Display · Futura")
                }

                Section {
                    ForEach(Font.readingSpecimen) { style in
                        SpecimenRow(style: style, sample: Self.readingSamples[style.id] ?? style.name)
                    }
                } header: {
                    SectionHeader("Reading · SF Pro")
                }

                Section {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("Question")
                            .font(.dsSectionHeader).textCase(.uppercase).tracking(0.6)
                            .foregroundStyle(Color.dsTextSecondary)
                        Text(Self.questionSample)
                            .font(.dsBody)
                            .foregroundStyle(Color.dsTextPrimary)
                        Text("NIST discussion")
                            .font(.dsSectionHeader).textCase(.uppercase).tracking(0.6)
                            .foregroundStyle(Color.dsTextSecondary)
                            .padding(.top, DS.Space.xs)
                        Text(Self.discussionSample)
                            .font(.dsBody)
                            .foregroundStyle(Color.dsTextSecondary)
                            .lineSpacing(2)
                    }
                    .padding(.vertical, DS.Space.xs)
                } header: {
                    SectionHeader("Long-form guidance")
                }

                Section {
                    ForEach(Self.identifierSamples, id: \.id) { sample in
                        HStack(alignment: .firstTextBaseline) {
                            RequirementIDLabel(id: sample.id)
                            Spacer()
                            Text(sample.framework)
                                .font(.dsFootnote)
                                .foregroundStyle(Color.dsTextSecondary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                        RequirementIDLabel(id: "AC-2(1)", size: .small)
                        RequirementIDLabel(id: "AC-2(1)")
                        RequirementIDLabel(id: "AC-2(1)", size: .large)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Identifier sizes: small, regular, large")
                } header: {
                    SectionHeader("Identifiers · SF Mono")
                }

                Section {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Button("Mark as Implemented") {}
                            .buttonStyle(.dsPrimary)
                        Button("Add Evidence") {}
                            .buttonStyle(.dsSecondary)
                        Button("Skip for Now") {}
                            .font(.dsButton)
                            .foregroundStyle(Color.dsAccent)
                    }
                    .padding(.vertical, DS.Space.xs)
                } header: {
                    SectionHeader("Buttons")
                }
            }
            .modifier(OptionalDynamicTypeSize(size: previewSize.dynamicTypeSize))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Type Specimen")
        .accessibilityIdentifier("screen.typeSpecimen")
    }

    static let displaySamples: [String: String] = [
        "largeTitle": "Assessments",
        "title": "64% implemented",
        "title2": "Account Management",
        "title3": "Organizational Context",
        "headline": "Govern",
        "sectionHeader": "Protect",
        "button": "Mark as Implemented",
    ]

    static let readingSamples: [String: String] = [
        "body": "Who can sign in to each of your systems, and how do you remove access when someone leaves?",
        "callout": "Organizations with U.S. Department of Defense contracts should confirm which revision of SP 800-171 their contract requires.",
        "subheadline": "Owner: IT Operations · Target: March 31",
        "footnote": "Source: NIST SP 800-53 Rev. 5, Release 5.2.0",
        "caption": "42 of 106 implemented",
    ]

    static let questionSample = "Does your organization keep a current list of the accounts on each system, including who owns each one and what it can access?"

    /// NIST SP 800-53 Rev. 5, AC-2 discussion (opening sentences).
    static let discussionSample = "Examples of system account types include individual, shared, group, system, guest, anonymous, emergency, developer, temporary, and service. Identification of authorized system users and the specification of access privileges reflect the requirements in other controls in the security plan."

    static let identifierSamples: [(id: String, framework: String)] = [
        ("GV.OC-01", "CSF 2.0 subcategory"),
        ("AC-2(1)", "SP 800-53 control enhancement"),
        ("03.01.01", "SP 800-171 requirement"),
    ]
}

/// Applies a dynamic type override only when one is selected, so the default follows the system.
private struct OptionalDynamicTypeSize: ViewModifier {
    let size: DynamicTypeSize?
    func body(content: Content) -> some View {
        if let size { content.dynamicTypeSize(size) } else { content }
    }
}

private struct SpecimenRow: View {
    let style: TypeStyle
    let sample: String
    var uppercase = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(sample)
                .font(style.font)
                .textCase(uppercase ? .uppercase : nil)
                .tracking(uppercase ? 0.6 : 0)
                .foregroundStyle(Color.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(style.name) · \(style.spec)")
                .font(.dsFootnote)
                .foregroundStyle(Color.dsTextSecondary)
            Text(style.usage)
                .font(.dsFootnote)
                .foregroundStyle(Color.dsTextTertiary)
        }
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}
