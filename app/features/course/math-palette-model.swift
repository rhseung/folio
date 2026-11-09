import FolioDomain
import FolioMarkdown
import Observation

/// The math palette under the note bar's f(x) (#392): the note's math syntax, which the button chose before the palette
/// came, then its symbols by category or by search. A pick goes to the editor's cursor through `pendingMath`.
@MainActor @Observable
final class MathPaletteModel {
    let editor: NoteEditorModel
    var category: MathCategory = .greek
    var search = ""

    init(editor: NoteEditorModel) {
        self.editor = editor
        category = categories.first ?? .greek
    }

    var syntax: MathSyntax {
        get { editor.meta.math }
        set { editor.meta.math = newValue }
    }

    var searching: Bool { !query.isEmpty }

    /// The tabs: categories with something in them, snippets first while settings have any for this syntax.
    var categories: [MathCategory] { groups().map(\.category) }

    /// The tab shown: the one picked, or the first when a change of syntax left it empty (no snippets in the other).
    var shown: MathCategory {
        let all = categories
        return all.contains(category) ? category : all.first ?? category
    }

    /// What the grid shows: the shown tab's symbols, or what every category finds while searching.
    var sections: [(category: MathCategory, items: [CompletionItem])] {
        if searching { return groups(matching: query) }
        let shown = shown
        return groups().filter { $0.category == shown }
    }

    func pick(_ item: CompletionItem) { editor.pendingMath = item }

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private func groups(matching typed: String = "") -> [(category: MathCategory, items: [CompletionItem])] {
        let snippets = NoteAssist(settings: editor.workspace.settings).snippets(syntax: syntax)
        return MathSymbols.groups(tex: syntax == .latex, snippets: snippets, matching: typed)
    }
}
