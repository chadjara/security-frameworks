import SwiftUI

@main
struct FrameworkApp: App {
    init() {
        NavigationBarStyle.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.dsAccent)
                .modifier(LaunchOverrides())
        }
    }
}

/// Launch arguments used by UI tests to capture screenshots in each appearance and text size.
/// Example: `-dsColorScheme dark -dsDynamicType ax3 -dsScreen typeSpecimen`.
enum LaunchOptions {
    static var colorScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "dsColorScheme") {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    static var dynamicTypeSize: DynamicTypeSize? {
        switch UserDefaults.standard.string(forKey: "dsDynamicType") {
        case "large": return .large
        case "xxxl": return .xxxLarge
        case "ax3": return .accessibility3
        case "ax5": return .accessibility5
        default: return nil
        }
    }

    static var initialScreen: DevelopmentScreen? {
        UserDefaults.standard.string(forKey: "dsScreen").flatMap(DevelopmentScreen.init(rawValue:))
    }
}

private struct LaunchOverrides: ViewModifier {
    func body(content: Content) -> some View {
        let sized: AnyView = {
            if let size = LaunchOptions.dynamicTypeSize { return AnyView(content.dynamicTypeSize(size)) }
            return AnyView(content)
        }()
        return sized.preferredColorScheme(LaunchOptions.colorScheme)
    }
}
