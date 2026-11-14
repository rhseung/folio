import Foundation

public struct CompletionCatalog: Sendable {
    public var slash: [CompletionItem]
    public var languages: [String]
    public var snippets: [Snippet]
    public var tex: Bool
    public var otherMath: [Snippet]

    public init(
        slash: [CompletionItem] = [], languages: [String] = [], snippets: [Snippet] = [], tex: Bool = true, otherMath: [Snippet] = []
    ) {
        self.slash = slash
        self.languages = languages
        self.snippets = snippets
        self.tex = tex
        self.otherMath = otherMath
    }

    public var fenceNames: [String] {
        MathFence.languages.map(\.name) + languages.filter { MathFence.syntax($0) == nil } + [CBWidget.language]
    }

    public func at(_ place: SourcePlace) -> CompletionCatalog {
        guard let fence = place.fence, (fence == .latex) != tex else { return self }
        var other = self
        other.tex = fence == .latex
        other.snippets = snippets.filter { !$0.inMath } + otherMath
        other.otherMath = snippets.filter(\.inMath)
        return other
    }
}
