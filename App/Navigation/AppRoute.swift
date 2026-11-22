import Foundation

/// Destinations shared by the iPhone stack navigation and the iPad split view.
enum AppRoute: Hashable {
    case requirements(frameworkID: String)
    case requirement(frameworkID: String, requirementID: String)
    case frameworkPreview(frameworkID: String)
    case frameworkSettings(frameworkID: String)
    case groupPreview(frameworkID: String, groupID: String)
    case assessment(UUID)
    case settings(SettingsPage)
}

enum SettingsPage: String, Hashable, CaseIterable {
    case about
    case dataStorage
    #if DEBUG
    case typeSpecimen
    case colorTokens
    case components
    case content
    #endif
}

/// Sidebar sections on iPad.
enum SidebarItem: Hashable {
    case framework(String)
    case explorer
    case assessments
    case settings
}

/// Launch arguments used by UI tests to open a specific screen with known data.
/// Example: `-uiRoute detail:csf-2.0:GV.OC-01 -uiSeed sample`. Available in debug builds only.
enum UITestRoute: Equatable {
    case home
    case list(String)
    case detail(String, String)
    case questionnaire(String)
    case explorer
    case preview(String)
    case scope(String)
    case newAssessment
    case assessments
    case settings

    static var current: UITestRoute? {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "uiRoute") else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 2).map(String.init)
        switch parts.first {
        case "home": return .home
        case "list" where parts.count > 1: return .list(parts[1])
        case "detail" where parts.count > 2: return .detail(parts[1], parts[2])
        case "questionnaire" where parts.count > 1: return .questionnaire(parts[1])
        case "explorer": return .explorer
        case "preview" where parts.count > 1: return .preview(parts[1])
        case "scope" where parts.count > 1: return .scope(parts[1])
        case "newAssessment": return .newAssessment
        case "assessments": return .assessments
        case "settings": return .settings
        default: return nil
        }
        #else
        return nil
        #endif
    }
}
