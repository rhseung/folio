import FolioDomain
import FolioMarkdown
import SwiftUI

@MainActor enum SlashBlocks {
    static func items(templates: [(NoteKind, [String])]) -> [CompletionItem] {
        func item(_ id: String, _ title: String, _ symbol: String, _ keywords: String, _ body: String, block: Bool = true) -> CompletionItem
        {
            CompletionItem(
                id: "slash.\(id)", title: title, symbol: symbol, keywords: keywords.split(separator: " ").map(String.init), body: body,
                block: block)
        }
        let fence = "```"
        var out = [
            item("h1", String(localized: .notesAssistHeading(1)), "textformat.size", "heading h1 title", "# "),
            item("h2", String(localized: .notesAssistHeading(2)), "textformat.size", "heading h2", "## "),
            item("h3", String(localized: .notesAssistHeading(3)), "textformat.size", "heading h3", "### "),
            item("bullets", String(localized: .notesAssistBullets), "list.bullet", "list bullet", "- "),
            item("numbers", String(localized: .notesAssistNumbers), "list.number", "list numbered ordered", "1. "),
            item("tasks", String(localized: .notesAssistTasks), "checklist", "todo task checkbox", "- [ ] "),
            item("quote", String(localized: .notesAssistQuote), "text.quote", "quote blockquote", "> "),
            item("callout", String(localized: .notesAssistCallout), "exclamationmark.bubble", "callout admonition", "> [!"),
            item("math", String(localized: .notesAssistMath), "function", "math equation latex display", "$$\n$1\n$$"),
            item("inline-math", String(localized: .notesAssistInlineMath), "x.squareroot", "math inline", "$$1$", block: false),
            item("code", String(localized: .notesAssistCode), "chevron.left.forwardslash.chevron.right", "code fence", fence),
            item("table", String(localized: .notesAssistTable), "tablecells", "table", "| $1 |  |\n| --- | --- |\n|  |  |"),
            item(
                "widget", String(localized: .notesAssistWidget), "square.on.square", "widget cb-widget",
                fence + "cb-widget\n{\"id\": \"$1\", \"height\": 320}\n" + fence),
            item("divider", String(localized: .notesAssistDivider), "minus", "divider rule hr", "---\n"),
            item("toc", String(localized: .notesAssistToc), "list.bullet.indent", "toc contents outline", "[TOC]\n"),
        ]
        for (kind, sections) in templates {
            let body = sections.enumerated().map { i, s in "## \(s)\n" + (i == 0 ? "$1\n" : "\n") }.joined(separator: "\n")
            out.append(item("template.\(kind.rawValue)", String(localized: .notesAssistTemplate(kind.label)), "doc.text", "template", body))
        }
        return out
    }

    static var guide: CompletionItem {
        CompletionItem(
            id: InputGuide.menuItemID, title: String(localized: .notesGuideTitle), detail: "⌘/", symbol: "keyboard",
            keywords: ["help", "guide", "shortcut"], body: "")
    }
}
