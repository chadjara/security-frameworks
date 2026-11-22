import Foundation

public struct ValidationIssue: Sendable, Hashable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }
    public let severity: Severity
    public let message: String

    public var description: String { "\(severity.rawValue): \(message)" }
}

/// Mirrors the converter's validation (tools/oscal_convert/validate.py) so the app can verify any
/// content file it loads, including files added after release.
public enum ContentValidator {
    public static func validate(_ doc: FrameworkDocument) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func error(_ m: String) { issues.append(ValidationIssue(severity: .error, message: "\(doc.id): \(m)")) }
        func warning(_ m: String) { issues.append(ValidationIssue(severity: .warning, message: "\(doc.id): \(m)")) }

        let framework = Framework(document: doc)
        let kinds = Set(doc.kinds.map(\.id))
        let baselines = Set(doc.baselines.map(\.id))

        var seen = Set<String>()
        for r in doc.requirements where !seen.insert(r.id).inserted { error("duplicate requirement id \(r.id)") }

        var groupIDs = Set<String>()
        var listed = Set<String>()
        var maxDepth = 0
        func walk(_ groups: [RequirementGroup], depth: Int) {
            for g in groups {
                maxDepth = max(maxDepth, depth)
                if !groupIDs.insert(g.id).inserted { error("duplicate group id \(g.id)") }
                if g.title.isEmpty { error("group \(g.id) has no title") }
                if !g.groups.isEmpty && !g.requirementIds.isEmpty { error("group \(g.id) has both subgroups and requirements") }
                for rid in g.requirementIds {
                    listed.insert(rid)
                    guard let r = framework.requirement(rid) else {
                        error("group \(g.id) lists unknown requirement \(rid)")
                        continue
                    }
                    if r.groupId != g.id { error("\(rid) is listed in \(g.id) but has groupId \(r.groupId)") }
                }
                walk(g.groups, depth: depth + 1)
            }
        }
        walk(doc.groups, depth: 0)
        if doc.groups.isEmpty { error("has no groups") }
        if maxDepth + 1 != doc.groupLevels.count { error("group depth \(maxDepth + 1) does not match groupLevels (\(doc.groupLevels.count))") }

        for r in doc.requirements {
            if r.title.isEmpty { error("\(r.id) has no title") }
            if r.statement.isEmpty { error("\(r.id) has no statement") }
            if !kinds.contains(r.kind) { error("\(r.id) has unknown kind \(r.kind)") }
            if !groupIDs.contains(r.groupId) { error("\(r.id) has unknown group \(r.groupId)") }
            if let parent = r.parentId {
                if framework.requirement(parent) == nil { error("\(r.id) has unknown parent \(parent)") }
            } else if !listed.contains(r.id) {
                error("top-level requirement \(r.id) is not listed in any group")
            }
            for b in r.baselines where !baselines.contains(b) { error("\(r.id) has unknown baseline \(b)") }
            for rel in r.related where framework.requirement(rel) == nil {
                warning("\(r.id) related requirement \(rel) is not active")
            }
            let scope = framework.parameterScope(for: r)
            var texts = r.statement.flatMap(\.flattened).compactMap(\.text)
            texts += r.parameters.flatMap(\.choices)
            for text in texts {
                for token in ParameterText.tokens(in: text) where scope[token] == nil {
                    error("\(r.id) references unknown parameter \(token)")
                }
            }
            for p in r.parameters {
                for part in p.aggregates where scope[part] == nil {
                    error("\(r.id) parameter \(p.id) aggregates unknown parameter \(part)")
                }
            }
            if !r.sourceUrl.hasPrefix("https://csrc.nist.gov/") { error("\(r.id) source URL is not on csrc.nist.gov") }
            if let e = r.editorial,
               e.question.isEmpty || e.whyItMatters.isEmpty || e.doneLooksLike.isEmpty || e.nextSteps.isEmpty {
                error("\(r.id) has incomplete editorial content")
            }
        }

        let keys = doc.requirements.map(\.sortKey)
        if keys != keys.sorted() { error("requirements are not in document order") }
        return issues
    }

    public static func validate(_ mapping: MappingDocument, frameworks: [String: Framework]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func error(_ m: String) { issues.append(ValidationIssue(severity: .error, message: "\(mapping.id): \(m)")) }
        guard let from = frameworks[mapping.fromFramework], let to = frameworks[mapping.toFramework] else {
            error("refers to a framework that is not installed (\(mapping.fromFramework) -> \(mapping.toFramework))")
            return issues
        }
        var seen = Set<String>()
        for e in mapping.entries {
            if !seen.insert(e.from).inserted { error("duplicate entry for \(e.from)") }
            if from.requirement(e.from) == nil { error("unknown source requirement \(e.from)") }
            if e.to.isEmpty { error("\(e.from) has no targets") }
            for t in e.to where to.requirement(t) == nil { error("\(e.from) -> unknown target \(t)") }
        }
        if mapping.source.url.isEmpty { error("has no source URL") }
        return issues
    }
}
