import SwiftData
import SwiftUI

@main
struct FrameworkApp: App {
    @State private var library = ContentLibrary()
    @State private var appLock = AppLock()
    @State private var entitlements = EntitlementManager()
    @Environment(\.scenePhase) private var scenePhase
    private let container: Result<ModelContainer, Error>

    init() {
        NavigationBarStyle.apply()
        ExportFiles.purge()
        container = Result { try Persistence.makeContainer(inMemory: LaunchOptions.usesInMemoryStore) }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let screen = LaunchOptions.initialScreen {
                    DevelopmentRootView(initialScreen: screen)
                } else {
                    switch container {
                    case .success(let container):
                        RootView()
                            .modelContainer(container)
                    case .failure(let error):
                        StoreUnavailableView(message: error.localizedDescription)
                    }
                }
            }
            .environment(library)
            .environment(appLock)
            .environment(entitlements)
            .tint(.dsAccent)
            .modifier(LaunchOverrides())
            .overlay {
                if appLock.isLocked {
                    LockScreenView()
                        .environment(appLock)
                        .transition(.opacity)
                } else if scenePhase != .active {
                    // Keeps assessment data out of the app switcher snapshot.
                    PrivacyCover()
                }
            }
            .onChange(of: scenePhase) { _, phase in appLock.sceneDidChange(to: phase) }
            .task { entitlements.start() }
        }
    }
}

/// Shown if the on-device store cannot be opened (for example, storage is full).
struct StoreUnavailableView: View {
    let message: String

    var body: some View {
        ErrorStateView(title: "Your assessments could not be opened",
                       message: "\(message) Free some storage on this device, then reopen the app. Your data has not been deleted.")
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
        #if DEBUG
        return UserDefaults.standard.string(forKey: "dsScreen").flatMap(DevelopmentScreen.init(rawValue:))
        #else
        return nil
        #endif
    }

    /// UI tests run against an empty in-memory store so they never touch real data.
    static var usesInMemoryStore: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "uiSeed") != nil || UserDefaults.standard.bool(forKey: "uiInMemory")
        #else
        return false
        #endif
    }

    static var seedScenario: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "uiSeed")
        #else
        return nil
        #endif
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
