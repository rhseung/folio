import Foundation
import RegexBuilder

// 노트의 확장 문법 목록이다. 문법마다 파서에 넘기기 전에 원문을 가리는 법, 편집 보기가 칠할 범위, 그린 HTML을 고치는
// 법을 한 곳에 둔다. 파서(`ParsedNote`), 편집 보기 스타일러, `HTMLRenderer`는 이 목록을 차례로 돌기만 한다. 목록의 차례가
// 곧 처리 차례다. 가리기는 대시 다음에 각주를, HTML은 위키링크, 맨 주소, 각주 순서로 고쳐야 결과가 같다.
// 편집 보기의 맨 주소는 FolioDomain의 `AppLink`로 읽어야 해서 앱의 스타일러가 이 목록 다음에 칠한다.
public struct NoteSyntax {
    private let mask: ((String) -> String)?
    private let spans: ((_ text: String, _ masked: String) -> [SourceSpan])?
    private let html: HTMLStep?

    // 바꾸지 않는 값이고, 노트를 그릴 때마다 정규식을 다시 만들지 않으려고 한 번만 만든다.
    nonisolated(unsafe) private static let all: [NoteSyntax] = [draftItem, blockID, escape, wikiLink, address, footnote]

    public static func masked(_ text: String) -> String {
        all.reduce(text) { text, syntax in syntax.mask?(text) ?? text }
    }

    // `masked`는 `masked(_:)`로 가린 원문이고 길이와 오프셋이 원문과 같다. 편집 보기는 수식을 더 가린 글을 넘긴다.
    public static func spans(in text: String, masked: String) -> [SourceSpan] {
        all.flatMap { $0.spans?(text, masked) ?? [] }
    }

    static func html(_ html: String, _ renderer: HTMLRenderer) -> String {
        all.reduce(html) { html, syntax in syntax.html?.apply(html, renderer) ?? html }
    }

    // MARK: 문법

    private static var draftItem: NoteSyntax {
        NoteSyntax(
            mask: DraftItem.mask,
            spans: { text, _ in
                DraftItem.dashes(in: text).map { SourceSpan(.listDash, NSRange(location: $0, length: 1), scope: nil) }
            },
            html: nil)
    }

    // 블록 ID는 블록 단위로 떼어 내므로 HTML은 렌더러가 블록을 그릴 때 고친다(`HTMLRenderer.splitBlockID`).
    private static var blockID: NoteSyntax {
        NoteSyntax(
            mask: nil,
            spans: { text, _ in
                lines(text).compactMap { line in
                    let s = (text as NSString).substring(with: line)
                    guard let m = s.firstMatch(of: BlockID.pattern) else { return nil }
                    let r = NSRange(m.range, in: s)
                    let mark = NSRange(location: line.location + r.location, length: r.length)
                    return SourceSpan(.blockID, NSRange(location: mark.location, length: 0), marks: [mark], scope: line)
                }
            },
            html: nil)
    }

    private static var escape: NoteSyntax {
        NoteSyntax(
            mask: nil,
            spans: { _, masked in
                escapePattern.matches(in: masked, range: NSRange(location: 0, length: (masked as NSString).length)).map {
                    SourceSpan(
                        .escape, NSRange(location: $0.range.location, length: 0), marks: [NSRange(location: $0.range.location, length: 1)],
                        scope: $0.range)
                }
            },
            html: nil)
    }

    private static var wikiLink: NoteSyntax {
        NoteSyntax(
            mask: nil,
            spans: { text, _ in
                text.matches(of: WikiLink.pattern).map { m in
                    let r = NSRange(m.range, in: text)
                    let link = WikiLink(m)
                    var marks = [
                        NSRange(location: r.location, length: m.1.isEmpty ? 2 : 3), NSRange(location: NSMaxRange(r) - 2, length: 2),
                    ]
                    if link.noteID != nil {
                        marks.append(NSRange(m.2.startIndex..<m.2.endIndex, in: text))
                        if let alias = m.5 {
                            let bar = text.index(before: alias.startIndex)
                            let escaped = bar > m.range.lowerBound && text[text.index(before: bar)] == "\\"
                            marks.append(NSRange((escaped ? text.index(before: bar) : bar)..<alias.startIndex, in: text))
                        }
                    }
                    return SourceSpan(.wikiLink(target: link.target), r, marks: marks, scope: r, tables: false, math: true)
                }
            },
            html: HTMLStep(
                skipping: codeOrMath, applies: { _, html in html.contains("[[") }, replace: { r, s in r.replaceWikiLinks(String(s)) }))
    }

    private static var address: NoteSyntax {
        NoteSyntax(
            mask: nil, spans: nil,
            html: HTMLStep(
                skipping: tagOrCodeOrMath, applies: { r, html in !r.inLink && html.localizedCaseInsensitiveContains("folio://") },
                replace: { _, s in
                    String(
                        s.replacing(/[Ff][Oo][Ll][Ii][Oo]:\/\/[^\s<>"'`(){}\[\]\\|&]+/) { m in
                            let written = String(m.0)
                            let kept = HTMLRenderer.trimmedAddress(written)
                            return "<a href=\"\(kept)\">\(kept)</a>" + written.dropFirst(kept.count)
                        })
                }))
    }

    private static var footnote: NoteSyntax {
        NoteSyntax(
            mask: Footnotes.mask,
            spans: { text, _ in
                Footnotes.marks(in: text).map { mark in
                    SourceSpan(
                        .footnote(definition: mark.definition), mark.label,
                        marks: [
                            NSRange(location: mark.range.location, length: mark.label.location - mark.range.location),
                            NSRange(location: NSMaxRange(mark.label), length: NSMaxRange(mark.range) - NSMaxRange(mark.label)),
                        ], scope: mark.range, math: true)
                }
            },
            html: HTMLStep(
                skipping: codeOrMath, applies: { r, html in r.footnotes != nil && html.contains("[^") },
                replace: { r, s in
                    guard let footnotes = r.footnotes else { return String(s) }
                    return String(
                        s.replacing(Footnotes.reference) { m in
                            guard let (n, use) = footnotes.use(HTMLRenderer.unescape(String(m.1))) else { return String(m.0) }
                            if r.nested { return "<sup class=\"footnote-ref\">\(n)</sup>" }
                            return
                                "<sup class=\"footnote-ref\"><a href=\"#fn-\(n)\" id=\"\(HTMLRenderer.footnoteRef(n, use))\">\(n)</a></sup>"
                        })
                }))
    }

    // MARK: 도우미

    // swiftlint:disable:next force_try
    static let escapePattern = try! NSRegularExpression(pattern: #"\\[!-/:-@\[-`{-~]"#)

    // 그린 HTML에서 고치지 않을 부분이다. 코드와 수식 안의 `[[`나 `[^1]`은 글자 그대로다.
    nonisolated(unsafe) private static let codeOrMath = Regex {
        ChoiceOf {
            /<code>.*?<\/code>/; /<span class="math">.*?<\/span>/
        }
    }
    // 맨 주소는 이미 링크인 글, 태그의 속성, 참조 미리보기의 `template`에서도 링크로 만들지 않는다. 여기서는 코드와 수식도
    // 줄을 넘어 찾는다.
    nonisolated(unsafe) private static let tagOrCodeOrMath = Regex {
        ChoiceOf {
            /<a\b[^>]*>.*?<\/a>/; codeOrMath; /<template\b.*?<\/template>/; /<[^>]*>/
        }
    }.dotMatchesNewlines()

    static func lines(_ text: String) -> [NSRange] {
        let ns = text as NSString
        var out: [NSRange] = []
        var start = 0
        while true {
            let r = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start))
            if r.location == NSNotFound {
                out.append(NSRange(location: start, length: ns.length - start))
                return out
            }
            out.append(NSRange(location: start, length: r.location - start))
            start = r.location + 1
        }
    }
}

private struct HTMLStep {
    let skipping: Regex<Substring>
    let applies: (HTMLRenderer, String) -> Bool
    let replace: (HTMLRenderer, Substring) -> String

    init(
        skipping: Regex<Substring>, applies: @escaping (HTMLRenderer, String) -> Bool,
        replace: @escaping (HTMLRenderer, Substring) -> String
    ) {
        self.skipping = skipping
        self.applies = applies
        self.replace = replace
    }

    func apply(_ html: String, _ renderer: HTMLRenderer) -> String {
        guard applies(renderer, html) else { return html }
        var out = ""
        var cursor = html.startIndex
        for m in html.matches(of: skipping) {
            out += replace(renderer, html[cursor..<m.range.lowerBound]) + html[m.range]
            cursor = m.range.upperBound
        }
        return out + replace(renderer, html[cursor...])
    }
}
