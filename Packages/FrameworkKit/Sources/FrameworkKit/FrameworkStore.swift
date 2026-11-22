import Foundation

/// Loads bundled framework content lazily and caches it. All decoding happens on this actor, off
/// the main thread.
///
/// Discovery: `index.json` is the fast path for the explorer. Any `*.framework.json` or
/// `*.mapping.json` file present in the content folder but missing from the index is also picked up,
/// so adding a framework only requires adding its data file.
public actor FrameworkStore {
    public let contentDirectory: URL
    private var cachedIndex: ContentIndex?
    private var frameworks: [String: Framework] = [:]
    private var searchIndexes: [String: SearchIndex] = [:]
    private var cachedGraph: MappingGraph?

    public init(contentDirectory: URL) {
        self.contentDirectory = contentDirectory
    }

    /// The `Content` folder copied into the app bundle.
    public static func bundled(_ bundle: Bundle = .main) -> FrameworkStore? {
        bundle.url(forResource: "Content", withExtension: nil).map(FrameworkStore.init(contentDirectory:))
    }

    // MARK: Index

    public func index() throws -> ContentIndex {
        if let cachedIndex { return cachedIndex }
        guard FileManager.default.fileExists(atPath: contentDirectory.path) else {
            throw ContentError.contentDirectoryMissing(contentDirectory.path)
        }
        let indexURL = contentDirectory.appendingPathComponent("index.json")
        var base: ContentIndex
        if FileManager.default.fileExists(atPath: indexURL.path) {
            base = try decode(ContentIndex.self, from: indexURL, name: "index.json")
            guard base.schemaVersion <= FrameworkDocument.supportedSchemaVersion else {
                throw ContentError.unsupportedSchemaVersion(found: base.schemaVersion,
                                                            supported: FrameworkDocument.supportedSchemaVersion)
            }
        } else {
            base = ContentIndex(schemaVersion: FrameworkDocument.supportedSchemaVersion, contentVersion: "unknown",
                                frameworks: [], mappings: [])
        }

        // Pick up framework files that the index does not list.
        let listedFiles = Set(base.frameworks.map(\.file))
        var entries = base.frameworks
        for file in contentFiles(in: "frameworks", suffix: ".framework.json") where !listedFiles.contains(file) {
            let doc = try decode(FrameworkDocument.self, from: contentDirectory.appendingPathComponent(file), name: file)
            if entries.contains(where: { $0.id == doc.id }) { continue }
            entries.append(FrameworkIndexEntry(document: doc, file: file))
            frameworks[doc.id] = Framework(document: doc)
        }
        let index = ContentIndex(schemaVersion: base.schemaVersion, contentVersion: base.contentVersion,
                                 frameworks: entries, mappings: base.mappings)
        cachedIndex = index
        return index
    }

    // MARK: Frameworks

    public func framework(_ id: String) throws -> Framework {
        if let cached = frameworks[id] { return cached }
        guard let entry = try index().frameworks.first(where: { $0.id == id }) else {
            throw ContentError.unknownFramework(id)
        }
        let url = contentDirectory.appendingPathComponent(entry.file)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ContentError.fileMissing(entry.file) }
        let framework = Framework(document: try decode(FrameworkDocument.self, from: url, name: entry.file))
        frameworks[id] = framework
        return framework
    }

    public func searchIndex(for id: String) throws -> SearchIndex {
        if let cached = searchIndexes[id] { return cached }
        let built = SearchIndex(framework: try framework(id))
        searchIndexes[id] = built
        return built
    }

    // MARK: Mappings

    public func mappingGraph() throws -> MappingGraph {
        if let cachedGraph { return cachedGraph }
        var files = Set(try index().mappings.map(\.file))
        files.formUnion(contentFiles(in: "mappings", suffix: ".mapping.json"))
        let docs = try files.sorted().map { file in
            try decode(MappingDocument.self, from: contentDirectory.appendingPathComponent(file), name: file)
        }
        let graph = MappingGraph(documents: docs)
        cachedGraph = graph
        return graph
    }

    // MARK: Validation

    /// Validates every installed framework and mapping. Used by tests and debug builds.
    public func validateAll() throws -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var loaded: [String: Framework] = [:]
        for entry in try index().frameworks {
            let fw = try framework(entry.id)
            loaded[fw.id] = fw
            issues += ContentValidator.validate(fw.document)
        }
        for doc in try mappingGraph().documents {
            issues += ContentValidator.validate(doc, frameworks: loaded)
        }
        return issues
    }

    // MARK: Helpers

    private func contentFiles(in folder: String, suffix: String) -> [String] {
        let dir = contentDirectory.appendingPathComponent(folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(suffix) }.sorted().map { "\(folder)/\($0)" }
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL, name: String) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ContentError.fileMissing(name)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as ContentError {
            throw error
        } catch let DecodingError.keyNotFound(key, context) {
            throw ContentError.decodingFailed(file: name, reason: "missing \(key.stringValue) at \(Self.path(context))")
        } catch let DecodingError.typeMismatch(_, context) {
            throw ContentError.decodingFailed(file: name, reason: "unexpected type at \(Self.path(context))")
        } catch let DecodingError.valueNotFound(_, context) {
            throw ContentError.decodingFailed(file: name, reason: "missing value at \(Self.path(context))")
        } catch let DecodingError.dataCorrupted(context) {
            throw ContentError.decodingFailed(file: name, reason: context.debugDescription)
        } catch {
            throw ContentError.decodingFailed(file: name, reason: String(describing: error))
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
}
