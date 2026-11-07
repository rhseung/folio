import Foundation

/// `[[target#heading|alias]]`, `[[target#^block]]`, `![[target]]` (embed), or an app object link
/// such as `[[material:<ID>#page=12]]`. A note is named by its title, or by its ID so a rename doesn't break the link:
/// `[[note:<ID>#heading|title]]`.
public struct WikiLink: Hashable, Sendable {
    public var target: String
    /// Text after `#` that is not a block reference: a heading, or `page=12` for object links.
    public var fragment: String?
    public var blockID: String?
    public var alias: String?
    public var isEmbed: Bool

    /// The app object's kind (`note`, `material`, `exam`, …), named as in a `folio://` link; nil for a note named by title.
    public var objectKind: String? {
        guard let colon = target.firstIndex(of: ":") else { return nil }
        let kind = String(target[..<colon])
        return WikiLink.objectKinds.contains(kind) ? kind : nil
    }

    public var objectID: UUID? {
        objectKind.flatMap { UUID(uuidString: String(target.dropFirst($0.count + 1))) }
    }

    public var noteID: UUID? { objectKind == "note" ? objectID : nil }

    /// The kinds of `folio://<kind>/<ID>` (FolioDomain's `AppLink`) that a note can link by ID. FolioMarkdown depends on no
    /// other Folio module, so the names are repeated here; `AppLinkWikiTests` checks both ways that they match the kinds
    /// that take an ID.
    public static let objectKinds: Set<String> = ["semester", "course", "session", "unit", "note", "material", "assignment", "exam", "card", "problem-set", "person"]

    public static var pattern: Regex<(Substring, Substring, Substring, Substring?, Substring?, Substring?)> {
        #/(!?)\[\[([^\]\|#]+)(?:#(\^?)([^\]\|]*))?(?:\|([^\]]*))?\]\]/#
    }

    public init(_ m: Regex<(Substring, Substring, Substring, Substring?, Substring?, Substring?)>.Match) {
        target = String(m.2).trimmingCharacters(in: .whitespaces)
        let isBlock = m.3 == "^"
        blockID = isBlock ? m.4.map(String.init) : nil
        fragment = isBlock ? nil : m.4.map(String.init)
        alias = m.5.map(String.init)
        isEmbed = m.1 == "!"
    }

    /// Where the link goes: `folio://<kind>/<ID>` for an app object, `folio://note/<title>` for a note, with the
    /// heading, block or page after `#`.
    public var href: String {
        let fragment = blockID.map { "#^" + $0 } ?? fragment.map { "#" + $0 } ?? ""
        if let kind = objectKind {
            return "folio://\(kind)/\(target.dropFirst(kind.count + 1))\(fragment)"
        }
        return "folio://note/\(target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target)\(fragment)"
    }

    public static func all(in text: String) -> [WikiLink] {
        text.matches(of: pattern).map(WikiLink.init)
    }

    /// `text` with links to the note `old` pointing at `new`, keeping each link's heading, block, alias and embed.
    /// Targets match ignoring case, as Obsidian and the notes list resolve them.
    public static func retargeted(_ text: String, from old: String, to new: String) -> String {
        text.replacing(pattern) { m in
            let target = m.2.trimmingCharacters(in: .whitespaces)
            guard target.caseInsensitiveCompare(old) == .orderedSame else { return String(m.0) }
            let fragment = m.4.map { "#\(m.3 ?? "")\($0)" } ?? ""
            return "\(m.1)[[\(new)\(fragment)\(m.5.map { "|\($0)" } ?? "")]]"
        }
    }

    /// `text` with links to the note `id` that still show its old title showing the new one. A name the writer chose
    /// instead of the title is theirs and stays.
    public static func retitled(_ text: String, note id: UUID, from old: String, to new: String) -> String {
        text.replacing(pattern) { m in
            guard WikiLink(m).noteID == id, let alias = m.5, alias.trimmingCharacters(in: .whitespaces) == old else { return String(m.0) }
            let fragment = m.4.map { "#\(m.3 ?? "")\($0)" } ?? ""
            return "\(m.1)[[\(m.2)\(fragment)|\(new)]]"
        }
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

    public static let numbered: Set<String> = ["definition", "theorem", "lemma", "corollary", "example", "counterexample"]

    public static let provable: Set<String> = ["theorem", "lemma", "corollary", "proposition"]

    /// Others still render, as plain callouts.
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
public enum BlockID {
    public static var pattern: Regex<(Substring, Substring)> { #/\s\^([A-Za-z0-9-]+)\s*$/# }

    public static func strip(_ text: String) -> (text: String, id: String?) {
        guard let m = text.firstMatch(of: pattern) else { return (text, nil) }
        var t = text
        t.removeSubrange(m.range)
        return (t, String(m.1))
    }
}
