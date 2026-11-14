import Foundation

public enum MathSymbols {
    public static func items(tex: Bool, snippets: [Snippet]) -> [CompletionItem] {
        groups(tex: tex, snippets: snippets).flatMap(\.items)
    }

    public static func groups(tex: Bool, snippets: [Snippet], matching typed: String = "") -> [(
        category: MathCategory, items: [CompletionItem]
    )] {
        let all = snippetItems(snippets, tex: tex) + (tex ? TeXCommands.all.map(\.item) : AsciiMathSymbols.items)
        let typed = typed.hasPrefix("\\") ? String(typed.dropFirst()) : typed
        return MathCategory.allCases.compactMap { category in
            let found = Completion.filter(all.filter { $0.category == category }, typed)
            return found.isEmpty ? nil : (category, found)
        }
    }

    static func snippetItems(_ snippets: [Snippet], tex: Bool) -> [CompletionItem] {
        snippets.enumerated().filter { $0.element.inMath && !$0.element.trigger.isEmpty }.map { i, s in
            let text = s.expanded.text
            return CompletionItem(
                id: "snippet.\(i).\(s.trigger)", title: s.trigger, detail: text, symbol: "text.insert", preview: sample(s.body),
                previewAsciiMath: !tex, body: s.body, category: .snippets)
        }
    }

    // 빈 인자(`\frac{}{}`)와 밑이 없는 첨자(`^{2}`)는 아무것도 그리지 않거나 숫자 하나만 그리므로, 표시 자리를 글자로
    // 채운다.
    static func sample(_ body: String) -> String {
        var letters = "abcdefghi".makeIterator()
        let filled = body.replacing(#/\$([0-9])/#) { $0.1 == "0" ? "" : String(letters.next() ?? "x") }
        return filled.hasPrefix("^") || filled.hasPrefix("_") ? "x" + filled : filled
    }

    // 수식 안에서는 기호 이름이 옆 글자와 붙지 않게 공백을 둔다. `\alphax`는 없는 명령이다.
    public static func insertion(_ item: CompletionItem, in text: NSString, selection: NSRange) -> SourceEditing.Edit {
        var (body, caret) = Snippet(trigger: "", body: item.body, inMath: true).expanded
        let place = SourcePlace.typing(at: selection.location, in: text)
        if place.isCode {
        } else if place.isMath {
            func letter(_ c: UInt16?) -> Bool { c.flatMap(Unicode.Scalar.init).map(CharacterSet.letters.contains) ?? false }
            let before = selection.location > 0 ? text.character(at: selection.location - 1) : nil
            let after = NSMaxRange(selection) < text.length ? text.character(at: NSMaxRange(selection)) : nil
            if letter(body.utf16.first), letter(before) {
                body = " " + body
                caret += 1
            }
            if letter(body.utf16.last), letter(after) { body += " " }
        } else {
            // 숫자로 시작하는 본문은 `$` 뒤에서 캐럿 표시로 읽히므로 먼저 펼친다.
            body = "$" + body + "$"
            caret += 1
        }
        return SourceEditing.Edit(range: selection, text: body, caret: selection.location + caret)
    }
}
