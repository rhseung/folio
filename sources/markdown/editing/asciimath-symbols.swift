import Foundation

// 출처는 asciimath2tex 1.5.0의 기호 표(`setup_symbols`)이고, 미리보기와 편집 보기가 쓰는 변환기와 같다. 메뉴는
// 낱말을 칠 때만 열리므로 글자로 된 이름만 둔다. 모든 예시는 목록을 만들 때 변환기의 `parse`로 이름이 남지 않고
// 변환되는지 확인했다.
public enum AsciiMathSymbols {
    public struct Symbol: Sendable, Equatable {
        public let name: String
        public let arguments: Int
        public let category: MathCategory

        public var sample: String {
            let fills = Self.fills[name] ?? ["a", "b"]
            return name + (0..<arguments).map { "(\(fills[min($0, fills.count - 1)]))" }.joined()
        }

        var item: CompletionItem {
            let body = name + (0..<arguments).map { "($\($0 + 1))" }.joined()
            return CompletionItem(
                id: "asciimath.\(name)", title: name, preview: Self.noPreview.contains(name) ? nil : sample,
                previewAsciiMath: true, body: body, category: category)
        }

        private static let fills: [String: [String]] = [
            "root": ["3", "x"], "color": ["red", "x"], "stackrel": ["!", "="], "overset": ["!", "="], "underset": ["n", "to"],
            "bb": ["R"], "bbb": ["R"], "cc": ["L"], "fr": ["g"], "text": ["text"],
        ]
        private static let noPreview: Set<String> = ["quad", "qquad", "and", "or", "if"]
    }

    private static let table: [(String, Int, MathCategory)] = {
        let groups: [(String, Int, MathCategory)] = [
            ("frac root", 2, .operators), ("stackrel overset underset color", 2, .fonts), ("sqrt", 1, .operators),
            (
                "abs norm floor ceil hat bar vec dot ddot tilde ul overline underline obrace ubrace cancel bb bbb cc tt sf fr text", 1,
                .fonts
            ),
            ("sum prod int oint lim", 0, .operators),
            (
                "alpha beta gamma delta epsilon varepsilon zeta eta theta vartheta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi varphi chi psi omega",
                0, .greek
            ),
            ("Gamma Delta Theta Lambda Xi Pi Sigma Phi Psi Omega", 0, .greek),
            ("xx div ox oplus odot cdot ast star circ nn uu nnn uuu vv wedge vee setminus", 0, .operators),
            ("in notin sub sup sube supe ne le ge lt gt approx cong equiv prop models vdash prec succ", 0, .relations),
            ("to rarr larr harr rArr lArr hArr uarr darr mapsto implies iff", 0, .arrows),
            ("AA EE not and or if", 0, .symbols),
            (
                "oo del grad aleph prime cdots ldots vdots ddots quad qquad angle triangle square therefore because CC NN QQ RR ZZ", 0,
                .symbols
            ),
            ("sin cos tan sec csc cot sinh cosh tanh arcsin arccos arctan log ln exp det dim gcd lcm min max mod", 0, .functions),
        ]
        return groups.flatMap { names, n, category in names.split(separator: " ").map { (String($0), n, category) } }
    }()

    public static let all: [Symbol] = table.map { Symbol(name: $0.0, arguments: $0.1, category: $0.2) }

    static let items: [CompletionItem] = all.map(\.item)
}
