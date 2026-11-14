import FolioDomain
import FolioMarkdown
import SwiftUI

struct NoteAssist: Equatable {
    var snippets: [MathSnippet] = MathSnippet.defaults
    var asciiSnippets: [MathSnippet] = MathSnippet.asciiMathDefaults
    var templates: [NoteKind: [String]] = [:]
    var links: (any NoteLinkSource)?

    init(
        snippets: [MathSnippet] = MathSnippet.defaults, asciiSnippets: [MathSnippet] = MathSnippet.asciiMathDefaults,
        templates: [NoteKind: [String]] = [:], links: (any NoteLinkSource)? = nil
    ) {
        self.snippets = snippets
        self.asciiSnippets = asciiSnippets
        self.templates = templates
        self.links = links
    }

    init(settings: FolioDomain.Settings, links: (any NoteLinkSource)? = nil) {
        snippets = settings.snippets
        asciiSnippets = settings.asciiSnippets
        templates = Dictionary(uniqueKeysWithValues: NoteAssist.templateKinds.map { ($0, settings.noteSections(for: $0)) })
        self.links = links
    }

    static func == (a: NoteAssist, b: NoteAssist) -> Bool {
        a.snippets == b.snippets && a.asciiSnippets == b.asciiSnippets && a.templates == b.templates && a.links === b.links
    }

    static let templateKinds: [NoteKind] = [.review, .examSummary, .unit]

    func snippets(syntax: MathSyntax) -> [Snippet] {
        let math =
            syntax == .latex
            ? snippets.filter(\.inMath) : asciiSnippets.map { MathSnippet(trigger: $0.trigger, body: $0.body, inMath: true) }
        return (snippets.filter { !$0.inMath } + math).map { Snippet(trigger: $0.trigger, body: $0.body, inMath: $0.inMath) }
    }

    @MainActor func catalog(syntax: MathSyntax) -> CompletionCatalog {
        let snippets = self.snippets(syntax: syntax)
        let other = self.snippets(syntax: syntax == .latex ? .asciimath : .latex).filter(\.inMath)
        let blocks = SlashBlocks.items(
            templates: Self.templateKinds.compactMap { kind in templates[kind].flatMap { $0.isEmpty ? nil : (kind, $0) } })
        return CompletionCatalog(
            slash: InputGuide.annotated(blocks + [SlashBlocks.guide], snippets: snippets),
            languages: NoteScripts.languages + ["mermaid"],
            snippets: snippets,
            tex: syntax == .latex,
            otherMath: other)
    }
}
