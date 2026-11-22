import FrameworkKit
import Foundation
import Observation

/// The bundled framework content, loaded once in the background and shared across the app.
@MainActor
@Observable
final class ContentLibrary {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var index: ContentIndex?
    private(set) var frameworks: [String: Framework] = [:]
    private(set) var mappingGraph: MappingGraph?
    @ObservationIgnored private let store: FrameworkStore?

    init(store: FrameworkStore? = FrameworkStore.bundled()) {
        self.store = store
    }

    func loadIfNeeded() async {
        guard phase == .idle else { return }
        await load()
    }

    func load() async {
        guard let store else {
            phase = .failed("The framework content folder is missing from the app. Reinstall the app to restore it.")
            return
        }
        phase = .loading
        do {
            let index = try await store.index()
            var loaded: [String: Framework] = [:]
            for entry in index.frameworks {
                loaded[entry.id] = try await store.framework(entry.id)
            }
            let graph = try await store.mappingGraph()
            self.index = index
            self.frameworks = loaded
            self.mappingGraph = graph
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Frameworks in index order.
    var entries: [FrameworkIndexEntry] { index?.frameworks ?? [] }
    var frameworkOrder: [String] { entries.map(\.id) }

    func framework(_ id: String) -> Framework? { frameworks[id] }
    func entry(_ id: String) -> FrameworkIndexEntry? { entries.first { $0.id == id } }

    func searchIndex(for id: String) async -> SearchIndex? {
        try? await store?.searchIndex(for: id)
    }
}
