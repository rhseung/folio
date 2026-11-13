// Places that broke a rule before the rule existed pass, a new place fails, and a listed place that is gone fails too
// until the list is rewritten, so the list only shrinks. Entries are a multiset: two identical calls in one file are two
// entries, and fixing one of them shows.
public enum Baseline {
    public struct Report {
        public let new: [Hit]
        public let gone: [String]

        public var passed: Bool { new.isEmpty && gone.isEmpty }
    }

    public static func entries(in text: String) -> [String] {
        text.split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    public static func compare(_ hits: [Hit], with entries: [String]) -> Report {
        var left = entries.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        var new: [Hit] = []
        for hit in hits.sorted(by: { ($0.path, $0.line) < ($1.path, $1.line) }) {
            if let count = left[hit.entry], count > 0 {
                left[hit.entry] = count - 1
            } else {
                new.append(hit)
            }
        }
        let gone = left.sorted { $0.key < $1.key }.flatMap { Array(repeating: $0.key, count: $0.value) }
        return Report(new: new, gone: gone)
    }

    public static func render(_ hits: [Hit]) -> String {
        let header = """
            # Places that broke a rule of folio-lint (sources/lint) before the rule existed. Fix one and delete its line.
            # Rewrite the list with `mise run check-code -- --update` only to drop fixed places or follow a moved one,
            # never to let a new one in.
            # check\tfile\twhat

            """
        return header + hits.map(\.entry).sorted().map { $0 + "\n" }.joined()
    }
}
