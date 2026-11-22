import Foundation

/// An sRGB color with WCAG 2.x luminance and contrast helpers. Platform-independent so the palette
/// can be verified by `swift test` without UIKit.
public struct RGB: Sendable, Hashable, CustomStringConvertible {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    public var description: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio between two colors (1...21).
    public static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let la = a.relativeLuminance, lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/// A color with light, dark, and increased-contrast variants.
public struct ColorToken: Sendable, Hashable, Identifiable {
    public enum Role: Sendable, Hashable {
        /// Body-size text: needs 4.5:1 against every background.
        case text
        /// Icons, glyphs, and large text: needs 3:1. Text-colored tokens are still held to 4.5:1 here.
        case graphic
        case background
    }

    public let id: String
    public let role: Role
    public let light: RGB
    public let dark: RGB
    public let lightHighContrast: RGB
    public let darkHighContrast: RGB

    public init(_ id: String, role: Role, light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) {
        self.id = id
        self.role = role
        self.light = RGB(hex: light)
        self.dark = RGB(hex: dark)
        self.lightHighContrast = RGB(hex: lightHC ?? light)
        self.darkHighContrast = RGB(hex: darkHC ?? dark)
    }
}

/// The app palette: one confident accent (ink blue), neutral grays, and four status colors.
/// Backgrounds mirror the iOS system grouped-list backgrounds so tokens can be checked against
/// what users actually see.
public enum Palette {
    // Backgrounds (match iOS system values).
    public static let background = ColorToken("background", role: .background, light: 0xFFFFFF, dark: 0x000000)
    public static let groupedBackground = ColorToken("groupedBackground", role: .background, light: 0xF2F2F7, dark: 0x000000)
    public static let groupedCell = ColorToken("groupedCell", role: .background, light: 0xFFFFFF, dark: 0x1C1C1E)
    public static let elevatedCell = ColorToken("elevatedCell", role: .background, light: 0xFFFFFF, dark: 0x2C2C2E)
    public static let backgrounds = [background, groupedBackground, groupedCell, elevatedCell]

    // Text.
    public static let textPrimary = ColorToken("textPrimary", role: .text, light: 0x000000, dark: 0xFFFFFF)
    public static let textSecondary = ColorToken("textSecondary", role: .text, light: 0x55555C, dark: 0xA3A3AA,
                                                 lightHC: 0x3D3D43, darkHC: 0xC7C7CD)
    public static let textTertiary = ColorToken("textTertiary", role: .text, light: 0x6A6A71, dark: 0x9A9AA1,
                                                lightHC: 0x505057, darkHC: 0xB5B5BC)

    // Accent.
    public static let accent = ColorToken("accent", role: .text, light: 0x1F4E8C, dark: 0x7FA8E0,
                                          lightHC: 0x163C70, darkHC: 0xA6C4EE)
    /// Text and glyphs drawn on an accent-filled surface.
    public static let onAccent = ColorToken("onAccent", role: .text, light: 0xFFFFFF, dark: 0x0A1626,
                                            lightHC: 0xFFFFFF, darkHC: 0x06101C)

    // Status.
    public static let statusNotStarted = ColorToken("statusNotStarted", role: .text, light: 0x66666D, dark: 0xA0A0A8,
                                                    lightHC: 0x4E4E55, darkHC: 0xBDBDC4)
    public static let statusInProgress = ColorToken("statusInProgress", role: .text, light: 0x8F5300, dark: 0xF0B24A,
                                                    lightHC: 0x6E4000, darkHC: 0xF7C873)
    public static let statusImplemented = ColorToken("statusImplemented", role: .text, light: 0x1C7536, dark: 0x5CC985,
                                                     lightHC: 0x135A29, darkHC: 0x86DCA6)
    public static let statusNotApplicable = ColorToken("statusNotApplicable", role: .text, light: 0x4D5A71, dark: 0x9DABC3,
                                                       lightHC: 0x3A4558, darkHC: 0xBAC6D9)

    public static let destructive = ColorToken("destructive", role: .text, light: 0xB3261E, dark: 0xFF8A80,
                                               lightHC: 0x8C1D17, darkHC: 0xFFADA6)

    /// Every token drawn on top of a background.
    public static let foregrounds = [textPrimary, textSecondary, textTertiary, accent, statusNotStarted,
                                     statusInProgress, statusImplemented, statusNotApplicable, destructive]

    public static let all = backgrounds + foregrounds + [onAccent]

    /// WCAG AA minimum for a role.
    public static func minimumContrast(for role: ColorToken.Role) -> Double {
        switch role {
        case .text: return 4.5
        case .graphic: return 3.0
        case .background: return 1.0
        }
    }
}

/// Spacing scale in points.
public enum Spacing {
    public static let xxs: Double = 4
    public static let xs: Double = 8
    public static let s: Double = 12
    public static let m: Double = 16
    public static let l: Double = 24
    public static let xl: Double = 32
    public static let xxl: Double = 48
    public static let scale: [Double] = [xxs, xs, s, m, l, xl, xxl]
}

/// Corner radius scale in points (use continuous corners).
public enum Radius {
    public static let small: Double = 6
    public static let medium: Double = 10
    public static let large: Double = 14
    public static let scale: [Double] = [small, medium, large]
}
