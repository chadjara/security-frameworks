import FrameworkKit
import SwiftUI

/// Status shown as symbol + text. Color is never the only cue.
struct StatusBadge: View {
    enum Style { case plain, tinted }

    let status: RequirementStatus
    var style: Style = .plain

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: status.symbolName)
            Text(status.title)
        }
        .font(.dsSubheadline.weight(.medium))
        .foregroundStyle(status.color)
        .padding(.horizontal, style == .tinted ? DS.Space.xs : 0)
        .padding(.vertical, style == .tinted ? DS.Space.xxs : 0)
        .background {
            if style == .tinted {
                RoundedRectangle(cornerRadius: DS.Corner.small, style: .continuous)
                    .fill(status.color.opacity(0.12))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(status.title)")
    }
}

/// A requirement identifier in SF Mono, e.g. GV.OC-01, AC-2(1), 03.01.01.
struct RequirementIDLabel: View {
    enum Size { case small, regular, large }

    let id: String
    var size: Size = .regular

    var body: some View {
        Text(id)
            .font(font)
            .foregroundStyle(Color.dsAccent)
            .accessibilityLabel(Self.spokenID(id))
    }

    private var font: Font {
        switch size {
        case .small: return .dsRequirementIDSmall
        case .regular: return .dsRequirementID
        case .large: return .dsRequirementIDLarge
        }
    }

    /// VoiceOver reads punctuation-heavy IDs character by character otherwise.
    static func spokenID(_ id: String) -> String {
        id.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "(", with: " enhancement ")
            .replacingOccurrences(of: ")", with: "")
    }
}

/// A requirement row: ID, title, optional status.
struct RequirementRow: View {
    let displayID: String
    let title: String
    var status: RequirementStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                RequirementIDLabel(id: displayID, size: .small)
                Spacer(minLength: DS.Space.xs)
                if let status {
                    Image(systemName: status.symbolName)
                        .foregroundStyle(status.color)
                        .accessibilityLabel(status.title)
                }
            }
            Text(title)
                .font(.dsBody)
                .foregroundStyle(Color.dsTextPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// An informational callout row for use inside a `List`.
struct NoticeView: View {
    let title: String
    let message: String
    var systemImage: String = "info.circle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.dsAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title).font(.dsHeadline).foregroundStyle(Color.dsTextPrimary)
                Text(message).font(.dsCallout).foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DS.Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// Label + value row that stacks vertically at accessibility text sizes.
struct KeyValueRow: View {
    let label: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DS.Space.s))
        layout {
            Text(label).font(.dsBody).foregroundStyle(Color.dsTextPrimary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: DS.Space.s) }
            Text(value).font(.dsBody.monospacedDigit()).foregroundStyle(Color.dsTextSecondary)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Section header text in Futura.
struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).dsSectionHeaderStyle() }
}

/// Progress shown as a thin bar with a text value for VoiceOver.
struct ProgressBar: View {
    let fraction: Double
    var tint: Color = .dsAccent

    var body: some View {
        ProgressView(value: min(max(fraction, 0), 1))
            .tint(tint)
            .accessibilityValue(Text("\(Int((fraction * 100).rounded())) percent"))
    }
}

/// Primary action button style: accent fill, Futura label, continuous corners.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsButton)
            .foregroundStyle(Color.dsOnAccent)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous)
                    .fill(Color.dsAccent.opacity(isEnabled ? 1 : 0.4))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
    }
}

/// Secondary action button style: accent text, Futura label.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsButton)
            .foregroundStyle(Color.dsAccent)
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous)
                    .strokeBorder(Color.dsAccent.opacity(0.5), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var dsPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var dsSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
