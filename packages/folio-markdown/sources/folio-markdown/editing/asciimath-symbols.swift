import Foundation

/// AsciiMath names offered on a word typed in an AsciiMath note's formula, in the order offered.
///
/// Source: the symbol tables of asciimath2tex 1.5.0 (`setup_symbols`: `greek_letters`, `relations`, `constants`,
/// `unary_symbols`, `binary_symbols`), the converter the preview and the edit view run (web/package.json,
/// web/src/math.js, web/src/native.js). Only names of letters are here, since only a word opens the menu; `->`, `!=`
/// and the like are typed as they are. Spellings that only repeat another (`Sin`, `lamda`, `epsi`) are left out. Every
/// sample here converts without its name left over (checked with the converter's `parse` when the list was made).
public enum AsciiMathSymbols {
    public struct Symbol: Sendable, Equatable {
        public let name: String
        public let arguments: Int
        public let category: MathCategory

        /// A formula showing it, its arguments filled in.
        public var sample: String {
            let fills = Self.fills[name] ?? ["a", "b"]
            return name + (0..<arguments).map { "(\(fills[min($0, fills.count - 1)]))" }.joined()
        }

        // Arguments in brackets, as AsciiMath groups them; Tab moves on through them as through TeX's braces
        // (`SourceEditing.slot`).
        var item: CompletionItem {
            let body = name + (0..<arguments).map { "($\($0 + 1))" }.joined()
            return CompletionItem(id: "asciimath.\(name)", title: name, preview: Self.noPreview.contains(name) ? nil : sample,
                                  previewAsciiMath: true, body: body, category: category)
        }

        private static let fills: [String: [String]] = [
            "root": ["3", "x"], "color": ["red", "x"], "stackrel": ["!", "="], "overset": ["!", "="], "underset": ["n", "to"],
            "bb": ["R"], "bbb": ["R"], "cc": ["L"], "fr": ["g"], "text": ["text"],
        ]
        /// Nothing to see on their own: spacing, and words the converter sets as text between spaces.
        private static let noPreview: Set<String> = ["quad", "qquad", "and", "or", "if"]
    }

    private static let table: [(String, Int, MathCategory)] = {
        let groups: [(String, Int, MathCategory)] = [
            // Structures first: what a formula is usually built around.
            ("frac root", 2, .operators), ("stackrel overset underset color", 2, .fonts), ("sqrt", 1, .operators),
            ("abs norm floor ceil hat bar vec dot ddot tilde ul overline underline obrace ubrace cancel bb bbb cc tt sf fr text", 1, .fonts),
            ("sum prod int oint lim", 0, .operators),
            // Greek.
            ("alpha beta gamma delta epsilon varepsilon zeta eta theta vartheta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi varphi chi psi omega", 0, .greek),
            ("Gamma Delta Theta Lambda Xi Pi Sigma Phi Psi Omega", 0, .greek),
            // Operators and relations.
            ("xx div ox oplus odot cdot ast star circ nn uu nnn uuu vv wedge vee setminus", 0, .operators),
            ("in notin sub sup sube supe ne le ge lt gt approx cong equiv prop models vdash prec succ", 0, .relations),
            ("to rarr larr harr rArr lArr hArr uarr darr mapsto implies iff", 0, .arrows),
            ("AA EE not and or if", 0, .symbols),
            ("oo del grad aleph prime cdots ldots vdots ddots quad qquad angle triangle square therefore because CC NN QQ RR ZZ", 0, .symbols),
            // Functions, written before their argument as `sin x` or `sin(x)`.
            ("sin cos tan sec csc cot sinh cosh tanh arcsin arccos arctan log ln exp det dim gcd lcm min max mod", 0, .functions),
        ]
        return groups.flatMap { names, n, category in names.split(separator: " ").map { (String($0), n, category) } }
    }()

    public static let all: [Symbol] = table.map { Symbol(name: $0.0, arguments: $0.1, category: $0.2) }

    static let items: [CompletionItem] = all.map(\.item)
}
