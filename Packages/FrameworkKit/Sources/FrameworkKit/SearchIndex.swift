import Foundation

public struct SearchHit: Sendable, Hashable {
    public let requirementID: String
    public let score: Float
}

/// An in-memory inverted index over requirement IDs, titles, statements, plain-language questions,
/// and discussion text. Built once per framework (off the main thread) and queried synchronously.
///
/// * Identifier queries ("AC-2", "ac-02(01)", "GV.OC", "3.1.1") match by segment, ignoring
///   punctuation and leading zeros.
/// * Text queries match every query word by prefix (all words must match).
public struct SearchIndex: Sendable {
    struct Posting: Sendable {
        let doc: Int32
        let weight: Float
    }

    enum Weight {
        static let title: Float = 3
        static let question: Float = 2.5
        static let statement: Float = 2
        static let examples: Float = 1.2
        static let discussion: Float = 1
    }

    private let docIDs: [String]
    private let idSegments: [[String]]
    private let tokens: [String]
    private let postings: [[Posting]]

    public var documentCount: Int { docIDs.count }

    public init(framework: Framework) {
        var docIDs: [String] = []
        var idSegments: [[String]] = []
        var table: [String: [Int32: Float]] = [:]

        for (i, r) in framework.requirements.enumerated() {
            let doc = Int32(i)
            docIDs.append(r.id)
            idSegments.append(Self.identifierSegments(r.displayId))
            let params = framework.parameterScope(for: r)

            func add(_ text: String?, _ weight: Float) {
                guard let text, !text.isEmpty else { return }
                for token in Self.tokenize(ParameterText.strippedForSearch(text, parameters: params)) {
                    let current = table[token, default: [:]][doc] ?? 0
                    if weight > current { table[token, default: [:]][doc] = weight }
                }
            }

            add(r.title, Weight.title)
            add(r.editorial?.question, Weight.question)
            for item in r.statement.flatMap(\.flattened) { add(item.text, Weight.statement) }
            for item in r.examples { add(item.text, Weight.examples) }
            add(r.discussion, Weight.discussion)
        }

        let sorted = table.keys.sorted()
        self.docIDs = docIDs
        self.idSegments = idSegments
        self.tokens = sorted
        self.postings = sorted.map { key in
            table[key]!.map { Posting(doc: $0.key, weight: $0.value) }.sorted { $0.doc < $1.doc }
        }
    }

    // MARK: Query

    public func search(_ query: String, limit: Int = 300) -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var scores: [Int32: Float] = [:]

        // Identifier match.
        let querySegments = Self.identifierSegments(trimmed)
        if !querySegments.isEmpty, trimmed.contains(where: \.isNumber) || querySegments.count > 1 {
            for (i, segs) in idSegments.enumerated() {
                if let s = Self.identifierScore(query: querySegments, id: segs) { scores[Int32(i), default: 0] += s }
            }
        }

        // Text match: every word must match some token by prefix.
        let words = Self.tokenize(trimmed, keepStopWords: false)
        if !words.isEmpty {
            var combined: [Int32: Float]?
            for word in words {
                var perWord: [Int32: Float] = [:]
                for idx in prefixRange(word) {
                    let exact = tokens[idx] == word
                    for p in postings[idx] {
                        let w = p.weight * (exact ? 1.5 : 1)
                        if w > perWord[p.doc] ?? 0 { perWord[p.doc] = w }
                    }
                }
                if let current = combined {
                    combined = current.filter { perWord[$0.key] != nil }.reduce(into: [:]) { acc, kv in
                        acc[kv.key] = kv.value + perWord[kv.key]!
                    }
                } else {
                    combined = perWord
                }
                if combined?.isEmpty == true { break }
            }
            for (doc, s) in combined ?? [:] { scores[doc, default: 0] += s }
        }

        return scores
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { SearchHit(requirementID: docIDs[Int($0.key)], score: $0.value) }
    }

    /// Indices of tokens that start with `prefix`, via binary search over the sorted token list.
    private func prefixRange(_ prefix: String) -> Range<Int> {
        var lo = 0, hi = tokens.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if tokens[mid] < prefix { lo = mid + 1 } else { hi = mid }
        }
        var end = lo
        while end < tokens.count, tokens[end].hasPrefix(prefix) { end += 1 }
        return lo..<end
    }

    // MARK: Tokenizing

    static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "in", "is", "it", "of", "on", "or",
        "that", "the", "to", "with",
    ]

    static func tokenize(_ text: String, keepStopWords: Bool = false) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var out: [String] = []
        var current = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return keepStopWords ? out : out.filter { !stopWords.contains($0) }
    }

    /// "AC-02(01)" -> ["ac", "2", "1"]; "GV.OC-01" -> ["gv", "oc", "1"]; "03.01.01" -> ["3", "1", "1"].
    static func identifierSegments(_ text: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var currentIsNumber = false
        func flush() {
            guard !current.isEmpty else { return }
            if currentIsNumber {
                let trimmed = current.drop { $0 == "0" }
                segments.append(trimmed.isEmpty ? "0" : String(trimmed))
            } else {
                segments.append(current)
            }
            current = ""
        }
        for ch in text.lowercased() {
            if ch.isNumber {
                if !currentIsNumber { flush() }
                currentIsNumber = true
                current.append(ch)
            } else if ch.isLetter {
                if currentIsNumber { flush() }
                currentIsNumber = false
                current.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return segments
    }

    static func identifierScore(query: [String], id: [String]) -> Float? {
        guard query.count <= id.count else { return nil }
        for i in 0..<(query.count - 1) where query[i] != id[i] { return nil }
        let last = query.count - 1
        if query[last] == id[last] {
            return query.count == id.count ? 100 : 40 - Float(id.count - query.count)
        }
        return id[last].hasPrefix(query[last]) ? 20 : nil
    }
}
