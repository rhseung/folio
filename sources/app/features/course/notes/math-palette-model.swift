import FolioDomain
import FolioMarkdown
import Observation

@MainActor @Observable
final class MathPaletteModel {
    let editor: NoteEditorModel
    var category: MathCategory = .greek
    var search = ""

    init(editor: NoteEditorModel) {
        self.editor = editor
        category = categories.first ?? .greek
    }

    var fence: MathSyntax?

    var syntax: MathSyntax {
        get { fence ?? editor.meta.math }
        set { if fence == nil { editor.meta.math = newValue } }
    }

    var searching: Bool { !query.isEmpty }

    var categories: [MathCategory] { groups().map(\.category) }

    var shown: MathCategory {
        let all = categories
        return all.contains(category) ? category : all.first ?? category
    }

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
