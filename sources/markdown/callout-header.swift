import Foundation

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

    public static let known: [String] = [
        "definition", "theorem", "lemma", "corollary", "proof", "example", "counterexample", "remark", "note", "tip",
        "warning", "important", "question", "solution", "summary", "abstract", "info", "danger",
    ]

    public var explicitNumber: String? {
        title.firstMatch(of: /^(?:[A-Za-z]+\s+)?(\d+(?:\.\d+)*)\b/).map { String($0.1) }
    }
}
