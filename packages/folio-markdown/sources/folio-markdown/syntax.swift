import Foundation

/// `[[target#heading|alias]]`, `[[target#^block]]`, `![[target]]` (embed), or an app object link
/// such as `[[material:<ID>#page=12]]` (docs/SPEC.md "지원 문법").
public struct WikiLink: Hashable, Sendable {
    public var target: String
    /// Text after `#` that is not a block reference: a heading, or `page=12` for object links.
    public var fragment: String?
    public var blockID: String?
    public var alias: String?
    public var isEmbed: Bool

    /// `material`, `unit`, `session`, `card`, `assignment` for app objects; nil for notes.
    public var objectKind: String? {
        guard let colon = target.firstIndex(of: ":") else { return nil }
        let kind = String(target[..<colon])
        return WikiLink.objectKinds.contains(kind) ? kind : nil
    }

    public var objectID: UUID? {
        objectKind.flatMap { UUID(uuidString: String(target.dropFirst($0.count + 1))) }
    }

    public static let objectKinds: Set<String> = ["material", "unit", "session", "card", "assignment"]

    static var pattern: Regex<(Substring, Substring, Substring, Substring?, Substring?, Substring?)> {
        #/(!?)\[\[([^\]\|#]+)(?:#(\^?)([^\]\|]*))?(?:\|([^\]]*))?\]\]/#
    }

    init(_ m: Regex<(Substring, Substring, Substring, Substring?, Substring?, Substring?)>.Match) {
        target = String(m.2).trimmingCharacters(in: .whitespaces)
        let isBlock = m.3 == "^"
        blockID = isBlock ? m.4.map(String.init) : nil
        fragment = isBlock ? nil : m.4.map(String.init)
        alias = m.5.map(String.init)
        isEmbed = m.1 == "!"
    }

    public static func all(in text: String) -> [WikiLink] {
        text.matches(of: pattern).map(WikiLink.init)
    }
}

/// Obsidian callout `> [!type]± title`. `-` means folded by default.
public struct CalloutHeader: Hashable, Sendable {
    public var type: String
    public var title: String
    public var folded: Bool

    static var pattern: Regex<(Substring, Substring, Substring, Substring)> { #/^\[!([A-Za-z-]+)\]([+-]?)[ \t]*(.*)$/# }

    public init?(line: String) {
        guard let m = line.wholeMatch(of: CalloutHeader.pattern) else { return nil }
        type = m.1.lowercased()
        folded = m.2 == "-"
        title = String(m.3)
    }

    /// Types numbered automatically within a note.
    public static let numbered: Set<String> = ["definition", "theorem", "lemma", "corollary", "example", "counterexample"]

    /// Statements a proof right below hangs from.
    public static let provable: Set<String> = ["theorem", "lemma", "corollary", "proposition"]

    /// Callout types the editor offers (docs/SPEC.md). Others still render, as plain callouts.
    public static let known: [String] = [
        "definition", "theorem", "lemma", "corollary", "proof", "example", "counterexample", "remark", "note", "tip",
        "warning", "important", "question", "solution", "summary", "abstract", "info", "danger",
    ]

    /// An explicit number in the title, e.g. `1.20` in `Theorem 1.20` or `1.20 (Cauchy)`.
    public var explicitNumber: String? {
        title.firstMatch(of: /^(?:[A-Za-z]+\s+)?(\d+(?:\.\d+)*)\b/).map { String($0.1) }
    }
}

/// `^block-id` at the end of a paragraph or list item.
enum BlockID {
    static var pattern: Regex<(Substring, Substring)> { #/\s\^([A-Za-z0-9-]+)\s*$/# }

    /// Splits a trailing block ID off `text`.
    static func strip(_ text: String) -> (text: String, id: String?) {
        guard let m = text.firstMatch(of: pattern) else { return (text, nil) }
        var t = text
        t.removeSubrange(m.range)
        return (t, String(m.1))
    }
}
