import SwiftUI

/// Phase 1 screens. Phase 2 replaces this root with the assessment experience.
enum DevelopmentScreen: String, CaseIterable, Identifiable, Hashable {
    case typeSpecimen
    case colorTokens
    case components
    case content

    var id: String { rawValue }

    var title: String {
        switch self {
        case .typeSpecimen: return "Type Specimen"
        case .colorTokens: return "Colors and Metrics"
        case .components: return "Components"
        case .content: return "Framework Content"
        }
    }

    var systemImage: String {
        switch self {
        case .typeSpecimen: return "textformat"
        case .colorTokens: return "paintpalette"
        case .components: return "square.grid.2x2"
        case .content: return "books.vertical"
        }
    }

    @MainActor @ViewBuilder var destination: some View {
        switch self {
        case .typeSpecimen: TypeSpecimenView()
        case .colorTokens: ColorTokensView()
        case .components: ComponentGalleryView()
        case .content: ContentOverviewView()
        }
    }
}

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: DevelopmentScreen? = LaunchOptions.initialScreen ?? .typeSpecimen
    @State private var path: [DevelopmentScreen] = LaunchOptions.initialScreen.map { [$0] } ?? []

    var body: some View {
        if horizontalSizeClass == .compact {
            NavigationStack(path: $path) {
                sidebarList
                    .navigationDestination(for: DevelopmentScreen.self) { $0.destination }
            }
        } else {
            NavigationSplitView {
                List(DevelopmentScreen.allCases, selection: $selection) { screen in
                    NavigationLink(value: screen) {
                        Label(screen.title, systemImage: screen.systemImage)
                    }
                    .accessibilityIdentifier("nav.\(screen.rawValue)")
                }
                .navigationTitle("Design System")
            } detail: {
                NavigationStack {
                    if let selection {
                        selection.destination
                    } else {
                        EmptyStateView(title: "Select a screen", message: "Choose a screen from the sidebar.",
                                       systemImage: "sidebar.left")
                    }
                }
            }
        }
    }

    private var sidebarList: some View {
        List(DevelopmentScreen.allCases) { screen in
            NavigationLink(value: screen) {
                Label(screen.title, systemImage: screen.systemImage)
            }
            .accessibilityIdentifier("nav.\(screen.rawValue)")
        }
        .navigationTitle("Design System")
    }
}
