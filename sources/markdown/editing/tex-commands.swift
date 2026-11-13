import Foundation

// 출처는 미리보기가 묶은 KaTeX 0.19.1의 지원 함수 목록이다. KaTeX에는 함수 목록을 내주는 API가 없고 그 표에는
// 그대로 치는 기호도 섞여 있어서, 목록을 손으로 관리한다. 모든 이름은 목록을 만들 때 `katex.renderToString`으로
// 그려지는지 확인했다.
public enum TeXCommands {
    public struct Command: Sendable, Equatable {
        public let name: String
        public let arguments: Int
        public let category: MathCategory

        public var sample: String {
            let fills = Self.fills[name] ?? ["a", "b"]
            return "\\" + name + (0..<arguments).map { "{\(fills[min($0, fills.count - 1)])}" }.joined()
        }

        var item: CompletionItem {
            let body = "\\" + name + (0..<arguments).map { "{$\($0 + 1)}" }.joined()
            return CompletionItem(
                id: "tex.\(name)", title: "\\" + name, preview: Self.noPreview.contains(name) ? nil : sample, body: body,
                category: category)
        }

        private static let fills: [String: [String]] = [
            "mathbb": ["R"], "mathcal": ["L"], "mathfrak": ["g"], "sqrt": ["x"], "text": ["text"], "textbf": ["text"],
            "textit": ["text"], "operatorname": ["rank"], "textcolor": ["red", "x"], "pmod": ["n"], "overset": ["!", "="],
            "stackrel": ["!", "="], "underset": ["n", "\\to"],
        ]
        private static let noPreview: Set<String> = ["quad", "qquad", "left", "right", "phantom", "not"]
    }

    private static let table: [(String, Int, MathCategory)] = {
        let groups: [(String, Int, MathCategory)] = [
            ("frac dfrac tfrac binom", 2, .operators), ("sqrt", 1, .operators),
            ("sum prod int iint iiint oint lim limsup liminf", 0, .operators),
            ("left right", 0, .fonts),
            ("text mathbb mathcal mathrm mathbf mathit mathsf mathtt mathfrak boldsymbol bm operatorname", 1, .fonts),
            ("hat widehat tilde widetilde bar overline underline vec overrightarrow dot ddot overbrace underbrace cancel boxed", 1, .fonts),
            ("overset underset stackrel textcolor", 2, .fonts), ("textbf textit", 1, .fonts), ("pmod", 1, .functions),
            ("phantom", 1, .fonts),
            (
                "alpha beta gamma delta epsilon varepsilon zeta eta theta vartheta iota kappa lambda mu nu xi pi varpi rho varrho sigma varsigma tau upsilon phi varphi chi psi omega",
                0, .greek
            ),
            ("Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega", 0, .greek),
            ("times div cdot pm mp ast star circ bullet oplus otimes odot cup cap setminus wedge vee", 0, .operators),
            (
                "le leq ge geq neq ne approx equiv sim simeq cong propto ll gg subset subseteq supset supseteq subsetneq in notin ni mid nmid parallel perp",
                0, .relations
            ),
            (
                "to rightarrow leftarrow Rightarrow Leftarrow leftrightarrow Leftrightarrow iff implies impliedby mapsto longrightarrow longleftarrow longmapsto uparrow downarrow",
                0, .arrows
            ),
            ("coprod bigcup bigcap bigoplus bigotimes bigvee bigwedge", 0, .operators), ("sup inf max min", 0, .functions),
            ("det gcd log ln lg exp sin cos tan sec csc cot arcsin arccos arctan sinh cosh tanh deg dim ker hom Pr arg", 0, .functions),
            (
                "infty partial nabla forall exists nexists emptyset varnothing neg lnot ldots cdots vdots ddots dots quad qquad prime angle triangle square Box aleph hbar ell Re Im wp top bot",
                0, .symbols
            ),
            ("not", 0, .relations), ("bmod", 0, .functions),
            ("langle rangle lfloor rfloor lceil rceil lvert rvert lVert rVert vert Vert", 0, .fonts), ("backslash checkmark", 0, .symbols),
        ]
        return groups.flatMap { names, n, category in names.split(separator: " ").map { (String($0), n, category) } }
    }()

    public static let all: [Command] = table.map { Command(name: $0.0, arguments: $0.1, category: $0.2) }

    public static let environments = [
        "pmatrix", "bmatrix", "matrix", "vmatrix", "Bmatrix", "Vmatrix", "smallmatrix", "cases", "dcases", "rcases",
        "aligned", "align", "align*", "gathered", "gather", "gather*", "equation", "equation*", "split",
    ]
}
