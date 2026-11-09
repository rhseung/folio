import Foundation

/// The groups a formula's symbols are browsed in, in the order shown: the whole list a bare `\` opens in the edit
/// view and the symbol palette both read them from `MathSymbols` (#392).
public enum MathCategory: String, CaseIterable, Sendable {
    case snippets, greek, relations, operators, arrows, functions
    /// Fonts, accents and brackets: what dresses or encloses another symbol.
    case fonts
    /// Constants, logic, dots and spacing, which none of the others hold.
    case symbols
}

public enum MathSymbols {
    /// Every candidate for a note's formulas, category by category: its math snippets, then its syntax's symbols
    /// (`TeXCommands` or `AsciiMathSymbols`), each category in the order completion offers them.
    public static func items(tex: Bool, snippets: [Snippet]) -> [CompletionItem] {
        groups(tex: tex, snippets: snippets).flatMap(\.items)
    }

    /// The categories with something in them, and what is in each; with `matching`, only what the typed text finds,
    /// best first within each. A TeX command is found with its `\` typed or not.
    public static func groups(tex: Bool, snippets: [Snippet], matching typed: String = "") -> [(category: MathCategory, items: [CompletionItem])] {
        let all = snippetItems(snippets, tex: tex) + (tex ? TeXCommands.all.map(\.item) : AsciiMathSymbols.items)
        let typed = typed.hasPrefix("\\") ? String(typed.dropFirst()) : typed
        return MathCategory.allCases.compactMap { category in
            let found = Completion.filter(all.filter { $0.category == category }, typed)
            return found.isEmpty ? nil : (category, found)
        }
    }

    // Numbered, as completion's are: settings don't stop two snippets sharing a trigger.
    static func snippetItems(_ snippets: [Snippet], tex: Bool) -> [CompletionItem] {
        snippets.enumerated().filter { $0.element.inMath && !$0.element.trigger.isEmpty }.map { i, s in
            let text = s.expanded.text
            return CompletionItem(id: "snippet.\(i).\(s.trigger)", title: s.trigger, detail: text, symbol: "text.insert", preview: sample(s.body),
                                  previewAsciiMath: !tex, body: s.body, category: .snippets)
        }
    }

    // Empty arguments (`\frac{}{}`) and a script with no base (`^{2}`) typeset to nothing or a lone digit, so the
    // marks are filled with letters, as a command's sample is.
    static func sample(_ body: String) -> String {
        var letters = "abcdefghi".makeIterator()
        let filled = body.replacing(#/\$([0-9])/#) { $0.1 == "0" ? "" : String(letters.next() ?? "x") }
        return filled.hasPrefix("^") || filled.hasPrefix("_") ? "x" + filled : filled
    }

    /// The edit that puts a symbol picked in the palette at the selection. In a formula it goes in as it is, a space
    /// keeping its name from running into the letters beside it (`\alpha x`, not `\alphax`, which is no command); outside
    /// one it goes in as an inline formula of its own, the caret left inside.
    public static func insertion(_ item: CompletionItem, in text: NSString, selection: NSRange) -> SourceEditing.Edit {
        var (body, caret) = Snippet(trigger: "", body: item.body, inMath: true).expanded
        if SourcePlace.typing(at: selection.location, in: text).isMath {
            func letter(_ c: UInt16?) -> Bool { c.flatMap(Unicode.Scalar.init).map(CharacterSet.letters.contains) ?? false }
            let before = selection.location > 0 ? text.character(at: selection.location - 1) : nil
            let after = NSMaxRange(selection) < text.length ? text.character(at: NSMaxRange(selection)) : nil
            if letter(body.utf16.first), letter(before) {
                body = " " + body
                caret += 1
            }
            if letter(body.utf16.last), letter(after) { body += " " }
        } else {
            // Expanded first: a body opening with a digit would read as a caret mark after the `$`.
            body = "$" + body + "$"
            caret += 1
        }
        return SourceEditing.Edit(range: selection, text: body, caret: selection.location + caret)
    }
}
