import DesignTokens
import SwiftUI

/// The palette with light and dark values and measured contrast against grouped-list cells.
struct ColorTokensView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            Section {
                ForEach(Palette.foregrounds) { token in
                    TokenRow(token: token, colorScheme: colorScheme)
                }
            } header: {
                SectionHeader("Foreground")
            } footer: {
                Text("Contrast is measured against list cells in the current appearance. Every foreground color meets WCAG AA (4.5:1) against every background, in light and dark mode. Automated tests enforce this.")
                    .font(.dsFootnote)
            }

            Section {
                HStack(spacing: DS.Space.m) {
                    Text("Continue")
                        .font(.dsButton)
                        .foregroundStyle(Color.dsOnAccent)
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.s)
                        .background(RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous).fill(Color.dsAccent))
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("On accent").font(.dsHeadline)
                        Text(ratioText(Palette.onAccent, on: Palette.accent))
                            .font(.dsFootnote.monospacedDigit())
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                }
                .padding(.vertical, DS.Space.xxs)
            } header: {
                SectionHeader("Filled controls")
            }

            Section {
                ForEach(Array(zip(["xxs", "xs", "s", "m", "l", "xl", "xxl"], Spacing.scale)), id: \.0) { name, value in
                    HStack(spacing: DS.Space.m) {
                        Text(name).font(.dsRequirementID).frame(width: 44, alignment: .leading)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.dsAccent.opacity(0.7))
                            .frame(width: CGFloat(value), height: 12)
                        Text("\(Int(value)) pt").font(.dsFootnote.monospacedDigit()).foregroundStyle(Color.dsTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                SectionHeader("Spacing")
            }

            Section {
                HStack(spacing: DS.Space.l) {
                    ForEach(Array(zip(["Small", "Medium", "Large"], Radius.scale)), id: \.0) { name, value in
                        VStack(spacing: DS.Space.xs) {
                            RoundedRectangle(cornerRadius: CGFloat(value), style: .continuous)
                                .strokeBorder(Color.dsAccent, lineWidth: 1.5)
                                .frame(width: 56, height: 40)
                            Text("\(name) \(Int(value))").font(.dsFootnote).foregroundStyle(Color.dsTextSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, DS.Space.xs)
            } header: {
                SectionHeader("Corner radius")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Colors and Metrics")
        .accessibilityIdentifier("screen.colorTokens")
    }

    private func ratioText(_ fg: ColorToken, on bg: ColorToken) -> String {
        let ratio = colorScheme == .dark ? RGB.contrastRatio(fg.dark, bg.dark) : RGB.contrastRatio(fg.light, bg.light)
        return String(format: "%.1f:1", ratio)
    }
}

private struct TokenRow: View {
    let token: ColorToken
    let colorScheme: ColorScheme

    var body: some View {
        let value = colorScheme == .dark ? token.dark : token.light
        let cell = colorScheme == .dark ? Palette.groupedCell.dark : Palette.groupedCell.light
        let ratio = RGB.contrastRatio(value, cell)
        HStack(spacing: DS.Space.m) {
            RoundedRectangle(cornerRadius: DS.Corner.small, style: .continuous)
                .fill(Color(token: token))
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.displayName(token.id)).font(.dsHeadline).foregroundStyle(Color(token: token))
                Group {
                    Text("Light \(token.light.description)")
                    Text("Dark  \(token.dark.description)")
                }
                .font(.dsFootnote.monospaced())
                .foregroundStyle(Color.dsTextSecondary)
            }
            Spacer(minLength: DS.Space.xs)
            Text(String(format: "%.1f:1", ratio))
                .font(.dsFootnote.monospacedDigit())
                .foregroundStyle(Color.dsTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    static func displayName(_ id: String) -> String {
        var out = ""
        for ch in id {
            if ch.isUppercase { out.append(" ") }
            out.append(ch)
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }
}
