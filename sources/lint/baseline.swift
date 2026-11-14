// 규칙이 생기기 전에 규칙을 어긴 자리는 통과하고, 새 자리는 실패한다. 목록에 있는데 사라진 자리도 목록을 다시 쓸 때까지
// 실패하므로, 목록은 줄어들기만 한다. 항목은 multiset이라 한 파일의 같은 호출 둘은 항목 둘이고, 하나를 고쳐도 그 변화가 드러난다.
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
