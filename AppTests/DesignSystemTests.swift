import DesignTokens
import FrameworkKit
import Testing
import UIKit
@testable import FrameworkApp

@Suite("Design system in the app")
@MainActor
struct DesignSystemTests {
    @Test("Futura faces used by the type scale are available without bundling")
    func futuraAvailable() {
        #expect(UIFont(name: Typeface.futuraBold, size: 17) != nil)
        #expect(UIFont(name: Typeface.futuraMedium, size: 17) != nil)
    }

    @Test("Dynamic colors resolve to the token values for each appearance and contrast setting")
    func dynamicColors() {
        let color = UIColor(token: Palette.accent)
        func hex(_ traits: UITraitCollection) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            return RGB(red: Double(r), green: Double(g), blue: Double(b)).description
        }
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let high = UITraitCollection(accessibilityContrast: .high)
        #expect(hex(light) == "#1F4E8C")
        #expect(hex(dark) == "#7FA8E0")
        #expect(hex(UITraitCollection(traitsFrom: [light, high])) == "#163C70")
        #expect(hex(UITraitCollection(traitsFrom: [dark, high])) == "#A6C4EE")
    }

    @Test("Requirement identifiers are spoken clearly by VoiceOver")
    func spokenIDs() {
        #expect(RequirementIDLabel.spokenID("AC-2(1)") == "AC 2 enhancement 1")
        #expect(RequirementIDLabel.spokenID("GV.OC-01") == "GV OC 01")
    }

    @Test("Every status has a distinct symbol")
    func statusSymbols() {
        #expect(Set(RequirementStatus.allCases.map(\.symbolName)).count == RequirementStatus.allCases.count)
    }
}

@Suite("Bundled content in the app")
struct AppContentTests {
    @Test("The Content folder is in the app bundle and loads")
    func bundledContentLoads() async throws {
        let store = try #require(FrameworkStore.bundled())
        let index = try await store.index()
        #expect(index.frameworks.map(\.id) == ["csf-2.0", "sp800-53r5", "sp800-171r3"])
        let errors = try await store.validateAll().filter { $0.severity == .error }
        #expect(errors.isEmpty)
    }
}
