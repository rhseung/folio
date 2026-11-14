import Foundation

public enum Completion {
    public static func query(in text: NSString, caret: Int, catalog: CompletionCatalog) -> CompletionQuery? {
        let place = SourcePlace.at(caret, in: text)
        let catalog = catalog.at(place)
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let content = SourceLines.content(line, in: text)
        let prefix = text.substring(with: NSRange(location: content.location, length: caret - content.location))
        let rest = text.substring(with: NSRange(location: caret, length: NSMaxRange(content) - caret))
        let next: UInt16? = caret < text.length ? text.character(at: caret) : nil

        func make(_ kind: CompletionQuery.Kind, _ typed: Substring, extra: Int = 0) -> CompletionQuery {
            let n = typed.utf16.count
            return CompletionQuery(kind: kind, text: String(typed), range: NSRange(location: caret - n, length: n + extra), place: place)
        }

        switch place {
        case .text:
            if let m = prefix.firstMatch(of: #/(!?)\[\[([^\[\]]*)$/#) {
                return link(m.2, embed: m.1 == "!", start: caret - m.2.utf16.count - 2, caret: caret, rest: rest, place: place)
            }
            if let m = prefix.wholeMatch(of: #/[ \t]*(?:>[ \t]?)+\[!([A-Za-z-]*)/#) {
                return make(.callout, m.1, extra: next == 0x5D ? 1 : 0)
            }
            if rest.trimmingCharacters(in: .whitespaces).isEmpty,
                let m = prefix.wholeMatch(of: #/ {0,3}(?:`{3,}|~{3,})([A-Za-z0-9+#._-]*)/#)
            {
                return make(.codeLanguage, m.1)
            }
            if let m = prefix.firstMatch(of: #/(?:^|[ \t])(\/[\p{L}\p{N}-]*)$/#) {
                return make(.slash, m.1.dropFirst(), extra: 0).widened(by: 1)
            }
            if let (snippet, range) = Snippet.match(catalog.snippets, in: text, caret: caret, place: place) {
                return CompletionQuery(kind: .snippet, text: snippet.trigger, range: range, place: place)
            }
        case .math(_, let content, _):
            guard catalog.tex else {
                if let m = prefix.firstMatch(of: #/(?:^|[^\\])\\([A-Za-z]*)$/#), caret - m.1.utf16.count - 1 >= content.location {
                    return make(.texCommand, m.1).widened(by: 1)
                }
                // 글자 하나는 변수이므로, 한 글자에서 제안하면 모든 수식에 메뉴가 뜬다.
                if let m = prefix.firstMatch(of: #/(?:^|[^A-Za-z\\])([A-Za-z]{2,})$/#), caret - m.1.utf16.count >= content.location,
                    !asciiMath(String(m.1), catalog: catalog).isEmpty
                {
                    return make(.asciiMath, m.1)
                }
                if let (snippet, range) = Snippet.match(catalog.snippets, in: text, caret: caret, place: place) {
                    return CompletionQuery(kind: .snippet, text: snippet.trigger, range: range, place: place)
                }
                return nil
            }
            if let m = prefix.firstMatch(of: #/\\begin\{([A-Za-z*]*)$/#) {
                return make(.texEnvironment, m.1, extra: next == 0x7D ? 1 : 0)
            }
            if let m = prefix.firstMatch(of: #/(?:^|[^\\])\\([A-Za-z]*)$/#) {
                return make(.texCommand, m.1).widened(by: 1)
            }
            if let (snippet, range) = Snippet.match(catalog.snippets, in: text, caret: caret, place: place) {
                return CompletionQuery(kind: .snippet, text: snippet.trigger, range: range, place: place)
            }
        case .code, .inlineCode:
            break
        }
        return nil
    }

    public static func items(for query: CompletionQuery, catalog: CompletionCatalog) -> [CompletionItem] {
        let catalog = catalog.at(query.place)
        switch query.kind {
        case .slash:
            return filter(catalog.slash, query.text)
        case .callout:
            return filter(CalloutHeader.known.map { CompletionItem(id: "callout.\($0)", title: $0, body: $0) }, query.text)
        case .codeLanguage:
            return filter(catalog.fenceNames.map { CompletionItem(id: "language.\($0)", title: $0, body: $0) }, query.text)
        case .texCommand:
            if query.text.isEmpty { return MathSymbols.items(tex: catalog.tex, snippets: catalog.snippets) }
            return filter(catalog.tex ? TeXCommands.all.map(\.item) : AsciiMathSymbols.items, query.text, prefixOnly: true)
        case .texEnvironment:
            return filter(
                TeXCommands.environments.map { CompletionItem(id: "env.\($0)", title: $0, body: $0) }, query.text, prefixOnly: true)
        case .snippet:
            return snippets(catalog, trigger: query.text, inMath: query.place.isMath)
        case .asciiMath:
            return asciiMath(query.text, catalog: catalog)
        case .link:
            return []
        }
    }

    // 설정은 두 스니펫이 같은 트리거를 쓰는 것을 막지 않는데 메뉴에는 서로 다른 id가 필요하므로 번호를 붙인다.
    static func snippets(_ catalog: CompletionCatalog, trigger: String, inMath: Bool) -> [CompletionItem] {
        catalog.snippets.enumerated().filter { $0.element.trigger == trigger && $0.element.inMath == inMath }.map { i, s in
            CompletionItem(id: "snippet.\(i).\(s.trigger)", title: s.trigger, detail: s.expanded.text, symbol: "text.insert", body: s.body)
        }
    }

    static func asciiMath(_ word: String, catalog: CompletionCatalog) -> [CompletionItem] {
        snippets(catalog, trigger: word, inMath: true) + filter(AsciiMathSymbols.items, word, prefixOnly: true)
    }

    static func link(_ inner: Substring, embed: Bool, start: Int, caret: Int, rest: String, place: SourcePlace) -> CompletionQuery? {
        guard !inner.contains("|") else { return nil }
        let tail = rest.prefixMatch(of: #/[^\[\]]*\]\]/#).map { String($0.0) }
        let alias = tail.flatMap { t in t.firstIndex(of: "|").map { String(t[t.index(after: $0)...].dropLast(2)) } }
        let range = NSRange(location: start, length: caret - start + (tail?.utf16.count ?? 0))
        func make(_ part: LinkQuery.Part, target: String, typed: Substring) -> CompletionQuery {
            CompletionQuery(
                kind: .link(LinkQuery(part: part, embed: embed, target: target, alias: alias)), text: String(typed), range: range,
                place: place)
        }

        guard let hash = inner.firstIndex(of: "#") else { return make(.target, target: "", typed: inner) }
        let target = inner[..<hash].trimmingCharacters(in: .whitespaces)
        let after = inner[inner.index(after: hash)...]
        guard !target.isEmpty else { return nil }
        if after.hasPrefix("^") { return make(.block, target: target, typed: after.dropFirst()) }
        if after.hasPrefix("page=") {
            let digits = after.dropFirst(5)
            return digits.allSatisfy({ $0.isASCII && $0.isNumber }) ? make(.page, target: target, typed: digits) : nil
        }
        return make(.heading, target: target, typed: after)
    }

    public static func filter(_ items: [CompletionItem], _ typed: String, prefixOnly: Bool = false) -> [CompletionItem] {
        let q = typed.lowercased()
        guard !q.isEmpty else { return items }
        func score(_ item: CompletionItem) -> Int? {
            let title = item.title.lowercased(), keys = item.keywords.map { $0.lowercased() }
            let bare = title.hasPrefix("\\") ? String(title.dropFirst()) : title
            if bare.hasPrefix(q) { return bare == q ? 0 : 1 }
            if keys.contains(where: { $0.hasPrefix(q) }) { return 2 }
            if prefixOnly { return nil }
            if bare.contains(q) { return 3 }
            if keys.contains(where: { $0.contains(q) }) { return 4 }
            return nil
        }
        return items.enumerated().compactMap { i, item in score(item).map { (item, $0, i) } }
            .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
            .map(\.0)
    }

    public static func edit(accepting item: CompletionItem, for query: CompletionQuery, in text: NSString) -> SourceEditing.Edit {
        if let caret = item.caret {
            return SourceEditing.Edit(range: query.range, text: item.body, caret: query.range.location + caret)
        }
        var body = item.body
        var range = query.range
        switch query.kind {
        case .callout:
            let after = NSMaxRange(range)
            let spaced = after < text.length && text.character(at: after) == 0x20
            body = item.body + "]" + (spaced ? "" : " ")
        case .codeLanguage:
            if fenceNeedsClosing(text, at: range.location) {
                let line = text.lineRange(for: NSRange(location: range.location, length: 0))
                let fence = text.substring(with: NSRange(location: line.location, length: range.location - line.location))
                    .trimmingCharacters(in: .whitespaces)
                body = item.body + "\n$0\n" + fence
            }
        case .texEnvironment:
            let display: Bool = if case .math(true, _, _) = query.place { true } else { false }
            body = display ? "\(item.body)}\n$1\n\\end{\(item.body)}" : "\(item.body)} $1 \\end{\(item.body)}"
        case .slash:
            let line = text.lineRange(for: NSRange(location: range.location, length: 0))
            let before = text.substring(with: NSRange(location: line.location, length: range.location - line.location))
            if item.block, !before.trimmingCharacters(in: .whitespaces).isEmpty {
                let trailing =
                    before.utf16.count - before.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression).utf16.count
                range = NSRange(location: range.location - trailing, length: range.length + trailing)
                body = "\n" + body
            }
        case .texCommand, .snippet, .asciiMath, .link:
            break
        }
        return Snippet(trigger: "", body: body, inMath: false).edit(replacing: range)
    }

    static func fenceNeedsClosing(_ text: NSString, at index: Int) -> Bool {
        let line = text.lineRange(for: NSRange(location: index, length: 0))
        guard let open = Fence(text.substring(with: SourceLines.content(line, in: text))) else { return false }
        var count = 0
        var at = NSMaxRange(line)
        while at < text.length {
            let next = text.lineRange(for: NSRange(location: at, length: 0))
            if let f = Fence(text.substring(with: SourceLines.content(next, in: text))), f.char == open.char { count += 1 }
            at = NSMaxRange(next)
        }
        return count % 2 == 0
    }
}
