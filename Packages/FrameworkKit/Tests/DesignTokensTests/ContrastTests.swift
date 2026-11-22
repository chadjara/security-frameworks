import Testing
@testable import DesignTokens

@Suite("WCAG contrast")
struct ContrastTests {
    @Test("Known contrast ratios")
    func knownRatios() {
        #expect(abs(RGB.contrastRatio(RGB(hex: 0x000000), RGB(hex: 0xFFFFFF)) - 21) < 0.001)
        #expect(abs(RGB.contrastRatio(RGB(hex: 0x777777), RGB(hex: 0xFFFFFF)) - 4.48) < 0.01)
        #expect(RGB.contrastRatio(RGB(hex: 0x1F4E8C), RGB(hex: 0xFFFFFF)) > 8)
    }

    @Test("Every foreground token meets AA on every background, in light and dark mode",
          arguments: Palette.foregrounds)
    func foregroundContrast(token: ColorToken) {
        let minimum = Palette.minimumContrast(for: token.role)
        for bg in Palette.backgrounds {
            let light = RGB.contrastRatio(token.light, bg.light)
            let dark = RGB.contrastRatio(token.dark, bg.dark)
            #expect(light >= minimum, "\(token.id) light \(token.light) on \(bg.id) \(bg.light): \(light)")
            #expect(dark >= minimum, "\(token.id) dark \(token.dark) on \(bg.id) \(bg.dark): \(dark)")
        }
    }

    @Test("Increased-contrast variants are at least as strong as the standard ones",
          arguments: Palette.foregrounds)
    func highContrastNeverWeaker(token: ColorToken) {
        for bg in Palette.backgrounds {
            #expect(RGB.contrastRatio(token.lightHighContrast, bg.light) >= RGB.contrastRatio(token.light, bg.light) - 0.001,
                    "\(token.id) light HC on \(bg.id)")
            #expect(RGB.contrastRatio(token.darkHighContrast, bg.dark) >= RGB.contrastRatio(token.dark, bg.dark) - 0.001,
                    "\(token.id) dark HC on \(bg.id)")
        }
    }

    @Test("Text on accent-filled controls meets AA")
    func onAccent() {
        let t = Palette.onAccent, a = Palette.accent
        #expect(RGB.contrastRatio(t.light, a.light) >= 4.5)
        #expect(RGB.contrastRatio(t.dark, a.dark) >= 4.5)
        #expect(RGB.contrastRatio(t.lightHighContrast, a.lightHighContrast) >= 4.5)
        #expect(RGB.contrastRatio(t.darkHighContrast, a.darkHighContrast) >= 4.5)
    }

    @Test("Status colors are distinguishable from each other")
    func statusColorsDiffer() {
        let statuses = [Palette.statusNotStarted, Palette.statusInProgress, Palette.statusImplemented, Palette.statusNotApplicable]
        #expect(Set(statuses.map(\.light)).count == 4)
        #expect(Set(statuses.map(\.dark)).count == 4)
    }

    @Test("Spacing and radius scales are increasing")
    func scales() {
        #expect(Spacing.scale == Spacing.scale.sorted())
        #expect(Radius.scale == Radius.scale.sorted())
        #expect(Spacing.scale.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
    }
}
