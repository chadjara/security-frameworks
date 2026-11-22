import Foundation

/// A run of requirement text: literal text or an organization-defined parameter slot.
public enum TextSegment: Sendable, Hashable {
    case text(String)
    /// `value` is the organization's value when set; otherwise show `placeholder`.
    case parameter(id: String, placeholder: String, value: String?)
}

/// Renders `{{param:ID}}` tokens in statement text.
public enum ParameterText {
    static let open = "{{param:"
    static let close = "}}"

    /// IDs referenced by tokens in `text`, in order.
    public static func tokens(in text: String) -> [String] {
        segments(in: text, parameters: [:], values: [:]).compactMap {
            if case .parameter(let id, _, _) = $0 { return id }
            return nil
        }
    }

    public static func segments(in text: String, parameters: [String: Parameter], values: [String: String]) -> [TextSegment] {
        var out: [TextSegment] = []
        var rest = Substring(text)
        while let start = rest.range(of: open) {
            if start.lowerBound > rest.startIndex {
                out.append(.text(String(rest[rest.startIndex..<start.lowerBound])))
            }
            let afterOpen = rest[start.upperBound...]
            guard let end = afterOpen.range(of: close) else {
                out.append(.text(String(rest[start.lowerBound...])))
                rest = rest[rest.endIndex...]
                break
            }
            let id = String(afterOpen[afterOpen.startIndex..<end.lowerBound])
            out.append(.parameter(id: id, placeholder: placeholder(for: id, parameters: parameters),
                                  value: value(for: id, parameters: parameters, values: values)))
            rest = afterOpen[end.upperBound...]
        }
        if !rest.isEmpty { out.append(.text(String(rest))) }
        return coalesced(out)
    }

    /// Merges adjacent literal runs (for example text before an unterminated token and the token itself).
    private static func coalesced(_ segments: [TextSegment]) -> [TextSegment] {
        var out: [TextSegment] = []
        for segment in segments {
            if case .text(let next) = segment, case .text(let previous)? = out.last {
                out[out.count - 1] = .text(previous + next)
            } else {
                out.append(segment)
            }
        }
        return out
    }

    /// Plain string with values filled in and unset parameters shown as `[placeholder]`.
    public static func plain(_ text: String, parameters: [String: Parameter], values: [String: String]) -> String {
        segments(in: text, parameters: parameters, values: values).map { segment in
            switch segment {
            case .text(let s): return s
            case .parameter(_, let placeholder, let value): return value ?? "[\(placeholder)]"
            }
        }.joined()
    }

    static func placeholder(for id: String, parameters: [String: Parameter]) -> String {
        guard let p = parameters[id] else { return "organization-defined value" }
        if p.isSelection && p.label == nil {
            let choices = p.choices.map { plain($0, parameters: parameters, values: [:]) }
            return p.allowsMultipleSelection ? "one or more of: " + choices.joined(separator: "; ")
                                             : "one of: " + choices.joined(separator: "; ")
        }
        return p.placeholder
    }

    /// Values are stored under the parameter's canonical `id`. An aggregate shows its parts' values.
    static func value(for id: String, parameters: [String: Parameter], values: [String: String]) -> String? {
        let canonical = parameters[id]?.id ?? id
        if let v = values[canonical]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
        if let p = parameters[canonical], p.isAggregate {
            let parts = p.aggregates.compactMap { values[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var seen = Set<String>()
            let unique = parts.filter { seen.insert($0).inserted }
            return unique.isEmpty ? nil : unique.joined(separator: "; ")
        }
        return nil
    }

    /// Statement text with tokens replaced, for search indexing and exports.
    public static func strippedForSearch(_ text: String, parameters: [String: Parameter]) -> String {
        plain(text, parameters: parameters, values: [:])
    }
}
