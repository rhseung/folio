import Foundation

/// A note editor snippet: `trigger` then Tab (or the completion menu) puts `body` in its place. `$1`, `$2` … in the
/// body mark where the caret goes; any other `$` is itself. `inMath` snippets expand only inside a TeX formula.
public struct MathSnippet: Codable, Sendable, Equatable, Hashable {
    public var trigger: String
    public var body: String
    public var inMath: Bool

    public init(trigger: String, body: String, inMath: Bool) {
        self.trigger = trigger
        self.body = body
        self.inMath = inMath
    }

    /// After Obsidian's LaTeX Suite, whose triggers notes' writers already type, kept to the ones TeX needs most.
    public static let defaults: [MathSnippet] = [
        MathSnippet(trigger: "mk", body: "$$1$", inMath: false),
        MathSnippet(trigger: "dm", body: "$$\n$1\n$$", inMath: false),
        MathSnippet(trigger: "//", body: "\\frac{$1}{$2}", inMath: true),
        MathSnippet(trigger: "sr", body: "^{2}", inMath: true),
        MathSnippet(trigger: "cb", body: "^{3}", inMath: true),
        MathSnippet(trigger: "rd", body: "^{$1}", inMath: true),
        MathSnippet(trigger: "sq", body: "\\sqrt{$1}", inMath: true),
        MathSnippet(trigger: "ooo", body: "\\infty", inMath: true),
        MathSnippet(trigger: "->", body: "\\to", inMath: true),
        MathSnippet(trigger: "<=", body: "\\le", inMath: true),
        MathSnippet(trigger: ">=", body: "\\ge", inMath: true),
        MathSnippet(trigger: "!=", body: "\\neq", inMath: true),
        MathSnippet(trigger: "sum", body: "\\sum_{$1}^{$2}", inMath: true),
        MathSnippet(trigger: "lim", body: "\\lim_{$1 \\to $2}", inMath: true),
        MathSnippet(trigger: "bb", body: "\\mathbb{$1}", inMath: true),
        MathSnippet(trigger: "pmat", body: "\\begin{pmatrix}\n$1\n\\end{pmatrix}", inMath: true),
        MathSnippet(trigger: "case", body: "\\begin{cases}\n$1\n\\end{cases}", inMath: true),
        MathSnippet(trigger: "@a", body: "\\alpha", inMath: true),
        MathSnippet(trigger: "@b", body: "\\beta", inMath: true),
        MathSnippet(trigger: "@l", body: "\\lambda", inMath: true),
        MathSnippet(trigger: "@e", body: "\\varepsilon", inMath: true),
    ]
}
