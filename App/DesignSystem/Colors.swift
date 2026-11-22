import DesignTokens
import FrameworkKit
import SwiftUI
import UIKit

extension UIColor {
    /// A dynamic color that resolves a design token for the current appearance and contrast setting.
    convenience init(token: ColorToken) {
        self.init(dynamicProvider: { traits in
            let dark = traits.userInterfaceStyle == .dark
            let high = traits.accessibilityContrast == .high
            let rgb: RGB
            switch (dark, high) {
            case (false, false): rgb = token.light
            case (false, true): rgb = token.lightHighContrast
            case (true, false): rgb = token.dark
            case (true, true): rgb = token.darkHighContrast
            }
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }
}

extension Color {
    init(token: ColorToken) { self.init(uiColor: UIColor(token: token)) }

    // Text
    static let dsTextPrimary = Color(token: Palette.textPrimary)
    static let dsTextSecondary = Color(token: Palette.textSecondary)
    static let dsTextTertiary = Color(token: Palette.textTertiary)

    // Accent
    static let dsAccent = Color(token: Palette.accent)
    static let dsOnAccent = Color(token: Palette.onAccent)

    // Status
    static let dsNotStarted = Color(token: Palette.statusNotStarted)
    static let dsInProgress = Color(token: Palette.statusInProgress)
    static let dsImplemented = Color(token: Palette.statusImplemented)
    static let dsNotApplicable = Color(token: Palette.statusNotApplicable)

    static let dsDestructive = Color(token: Palette.destructive)

    // Backgrounds: the system grouped-list colors (the palette mirrors their values for contrast checks).
    static let dsGroupedBackground = Color(uiColor: .systemGroupedBackground)
    static let dsGroupedCell = Color(uiColor: .secondarySystemGroupedBackground)
    static let dsBackground = Color(uiColor: .systemBackground)
}

extension RequirementStatus {
    var color: Color {
        switch self {
        case .notStarted: return .dsNotStarted
        case .inProgress: return .dsInProgress
        case .implemented: return .dsImplemented
        case .notApplicable: return .dsNotApplicable
        }
    }

    /// Each status has a distinct symbol so color is never the only cue.
    var symbolName: String {
        switch self {
        case .notStarted: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .implemented: return "checkmark.circle.fill"
        case .notApplicable: return "minus.circle"
        }
    }
}
