@testable import FolioMarkdown
import Foundation
import Testing

/// Text with the selection marked: `|` for the caret, `«…»` for selected text.
struct Marked {
    let text: NSString
    let selection: NSRange

    init(_ s: String) {
        if let a = s.range(of: "«"), let b = s.range(of: "»") {
            let start = s.distance(from: s.startIndex, to: a.lowerBound)
            let inner = s[a.upperBound..<b.lowerBound]
            let plain = s.replacingOccurrences(of: "«", with: "").replacingOccurrences(of: "»", with: "")
            let loc = (String(plain.prefix(start)) as NSString).length
            text = plain as NSString
            selection = NSRange(location: loc, length: (String(inner) as NSString).length)
        } else {
            let r = (s as NSString).range(of: "|")
            text = (s as NSString).replacingCharacters(in: r, with: "") as NSString
            selection = NSRange(location: r.location, length: 0)
        }
    }

    static func show(_ text: NSString, _ edit: SourceEditing.Edit) -> String {
        let out = edit.applied(to: text) as NSString
        if edit.selected > 0 {
            return out.replacingCharacters(in: edit.selection, with: "«" + out.substring(with: edit.selection) + "»")
        }
        return out.replacingCharacters(in: NSRange(location: edit.caret, length: 0), with: "|")
    }
}

func typing(_ s: String, _ typed: String) -> String? {
    let m = Marked(s)
    return SourceEditing.typed(typed, in: m.text, selection: m.selection).map { Marked.show(m.text, $0) }
}

struct SourcePlaceTests {
    func place(_ s: String) -> SourcePlace {
        let m = Marked(s)
        return SourcePlace.at(m.selection.location, in: m.text)
    }

    @Test func readsCodeMathAndText() {
        #expect(place("본문|") == .text)
        #expect(place("```swift\nlet a|\n```") == .code(language: "swift"))
        #expect(place("```swift\nlet a\n```\n뒤|") == .text)
        #expect(place("``|`") == .text)
        #expect(place("앞 `co|de` 뒤") == .inlineCode)
        #expect(place("앞 `code` 뒤|") == .text)
        #expect(place("값 $x^|2$ 끝").isMath)
        #expect(place("값 $x^2$ 끝|") == .text)
        #expect(place("$|$").isMath)
        #expect(place("$$\nx|\n$$").isMath)
        #expect(place("$$\nx\n$$\n뒤|") == .text)
        #expect(place("$$|$$").isMath)
        #expect(place("가격은 \\$5|") == .text)
        if case .math(false, let content, _) = place("값 $\\frac{a}{|b}$") {
            #expect(content == NSRange(location: 3, length: 11))
        } else {
            Issue.record("not math")
        }
    }
}

struct PairTests {
    @Test func bracketsPairAndStepOver() {
        #expect(typing("|", "(") == "(|)")
        #expect(typing("a |b", "(") == nil)
        #expect(typing("(a|)", ")") == "(a)|")
        #expect(typing("|", "[") == "[|]")
        #expect(typing("[|]", "[") == "[[|]]")
        #expect(typing("|", "{") == "{|}")
    }

    @Test func dollarsMakeInlineThenDisplayMath() {
        #expect(typing("값 |", "$") == "값 $|$")
        #expect(typing("값 $|$", "$") == "값 $$|$$")
        #expect(typing("$x|$", "$") == "$x$|")
        #expect(typing("US|", "$") == nil)
    }

    @Test func backticksPairButThreeMakeAFence() {
        #expect(typing("|", "`") == "`|`")
        #expect(typing("`|`", "`") == "``|")
        #expect(typing("``|", "`") == nil)
        #expect(typing("`code|`", "`") == "`code`|")
    }

    @Test func boldPairsOnTheSecondStar() {
        #expect(typing("|", "*") == nil)
        #expect(typing("*|", "*") == "**|**")
        #expect(typing("**굵게|**", "*") == "**굵게*|*")
        #expect(typing("**굵게*|*", "*") == "**굵게**|")
    }

    @Test func aSelectionIsWrapped() {
        #expect(typing("«굵게»", "*") == "*«굵게»*")
        #expect(typing("«x»", "$") == "$«x»$")
        #expect(typing("«code»", "`") == "`«code»`")
        #expect(typing("«링크»", "[") == "[«링크»]")
        #expect(typing("«a»", "(") == "(«a»)")
        #expect(typing("«a»", "!") == nil)
    }

    @Test func codeBlocksPairOnlyBrackets() {
        #expect(typing("```js\nf|\n```", "(") == "```js\nf(|)\n```")
        #expect(typing("```js\na *|\n```", "*") == nil)
        #expect(typing("```js\n|\n```", "`") == nil)
        #expect(typing("```js\n|\n```", "$") == nil)
        #expect(typing("```js\n«a»\n```", "*") == nil)
        #expect(typing("`a|`", "*") == nil)
    }

    @Test func backspaceTakesAnEmptyPair() {
        func back(_ s: String) -> String? {
            let m = Marked(s)
            return SourceEditing.deleteBackward(in: m.text, selection: m.selection).map { Marked.show(m.text, $0) }
        }
        #expect(back("(|)") == "|")
        #expect(back("$$|$$") == "$|$")
        #expect(back("$|$") == "|")
        #expect(back("**|**") == "*|*")
        #expect(back("`|`") == "|")
        #expect(back("(a|)") == nil)
        #expect(back("```py\n*|*\n```") == nil)
    }
}

struct ListEditingTests {
    func enter(_ s: String) -> String? {
        let m = Marked(s)
        return SourceEditing.newline(m.text, m.selection, inCode: false).map { Marked.show(m.text, $0) }
    }

    func tab(_ s: String, back: Bool = false, snippets: [Snippet] = []) -> String {
        let m = Marked(s)
        return Marked.show(m.text, SourceEditing.tab(m.text, m.selection, back: back, snippets: snippets))
    }

    @Test func enterCarriesListsAndQuotesOn() {
        #expect(enter("- 하나|") == "- 하나\n- |")
        #expect(enter("- [x] 했다|") == "- [x] 했다\n- [ ] |")
        #expect(enter("> 인용|") == "> 인용\n> |")
        #expect(enter("1. 첫째|") == "1. 첫째\n2. |")
        #expect(enter("본문|") == nil)
    }

    @Test func enterOnAnEmptyItemEndsTheList() {
        #expect(enter("- 하나\n- |") == "- 하나\n\n|")
        #expect(enter("- 하나\n    - |") == "- 하나\n- |")
    }

    @Test func enterInTheMiddleNumbersTheRestOn() {
        #expect(enter("1. 하나|\n2. 둘\n3. 셋") == "1. 하나\n2. |\n3. 둘\n4. 셋")
    }

    @Test func tabNestsAndNumbersAgain() {
        #expect(tab("1. 하나\n2. 둘|\n3. 셋") == "1. 하나\n    1. 둘|\n2. 셋")
        #expect(tab("1. 하나\n    1. 둘|\n2. 셋", back: true) == "1. 하나\n2. 둘|\n3. 셋")
        #expect(tab("3. 셋|\n4. 넷", back: true) == "3. 셋|\n4. 넷")
        #expect(tab("- 하나\n- 둘|") == "- 하나\n    - 둘|")
    }

    @Test func tabInCodeOnlyIndents() {
        #expect(tab("```markdown\n1. a\n1. b|\n1. c\n```") == "```markdown\n1. a\n    1. b|\n1. c\n```")
        // A list right against a code block is numbered on its own.
        #expect(tab("1. a\n2. b|\n```\n1. x\n```") == "1. a\n    1. b|\n```\n1. x\n```")
    }

    @Test func renumberingKeepsAListsStartAndSkipsOtherLists() {
        let text = "5. a\n7. b\n\n1. c\n1. d" as NSString
        let changes = SourceEditing.renumber(text, around: NSRange(location: 0, length: 0))
        #expect(changes.map(\.1) == ["6"])
    }

    @Test func tabMovesThroughAFormulasArguments() {
        #expect(tab("$\\frac{|}{}$") == "$\\frac{}{|}$")
        #expect(tab("$\\frac{a}{|}$") == "$\\frac{a}{}$|")
        #expect(tab("$\\frac{a}{|}$", back: true) == "$\\frac{|a}{}$")
        #expect(tab("$$\n\\sqrt{|}\n$$") == "$$\n\\sqrt{}\n$$|")
    }

    @Test func tabExpandsSnippets() {
        let snippets = [Snippet(trigger: "mk", body: "$$1$", inMath: false), Snippet(trigger: "//", body: "\\frac{$1}{$2}", inMath: true),
                        Snippet(trigger: "dm", body: "$$\n$1\n$$", inMath: false)]
        #expect(tab("값 mk|", snippets: snippets) == "값 $|$")
        #expect(tab("bookmk|", snippets: snippets) == "    bookmk|")
        #expect(tab("$a //|$", snippets: snippets) == "$a \\frac{|}{}$")
        #expect(tab("dm|", snippets: snippets) == "$$\n|\n$$")
        // A math snippet doesn't fire in text, nor a text one in math.
        #expect(tab("//|", snippets: snippets) == "    //|")
        #expect(tab("$mk|$", snippets: snippets) == "$mk$|")
    }
}

struct CompletionTests {
    let catalog = CompletionCatalog(
        slash: [CompletionItem(id: "table", title: "표", keywords: ["table"], body: "| $1 |  |\n| --- | --- |", block: true),
                CompletionItem(id: "math", title: "수식", keywords: ["math"], body: "$$1$")],
        languages: ["python", "swift"],
        snippets: [Snippet(trigger: "mk", body: "$$1$", inMath: false)])

    func query(_ s: String, tex: Bool = true) -> CompletionQuery? {
        let m = Marked(s)
        var catalog = catalog
        catalog.tex = tex
        return Completion.query(in: m.text, caret: m.selection.location, catalog: catalog)
    }

    func accept(_ s: String, _ pick: (([CompletionItem]) -> CompletionItem?) = { $0.first }) -> String? {
        let m = Marked(s)
        guard let q = Completion.query(in: m.text, caret: m.selection.location, catalog: catalog),
              let item = pick(Completion.items(for: q, catalog: catalog)) else { return nil }
        return Marked.show(m.text, Completion.edit(accepting: item, for: q, in: m.text))
    }

    @Test func findsWhatIsBeingTyped() {
        #expect(query("/|")?.kind == .slash)
        #expect(query("앞 /ta|")?.text == "ta")
        #expect(query("a/b|") == nil)
        #expect(query("> [!no|]")?.kind == .callout)
        #expect(query("```py|")?.kind == .codeLanguage)
        #expect(query("```py\nx\n```|") == nil)
        #expect(query("$\\fr|$")?.kind == .texCommand)
        // AsciiMath has no commands, but a `\` asks for its names all the same.
        #expect(query("$\\fr|$", tex: false)?.kind == .texCommand)
        #expect(query("$\\\\|$") == nil)
        #expect(query("$\\begin{pm|}$")?.kind == .texEnvironment)
        #expect(query("값 mk|")?.kind == .snippet)
        #expect(query("`/|`") == nil)
    }

    @Test func filtersByNameThenKeyword() {
        let items = Completion.items(for: query("/ta|")!, catalog: catalog)
        #expect(items.map(\.id) == ["table"])
        #expect(Completion.items(for: query("/표|")!, catalog: catalog).map(\.id) == ["table"])
        #expect(Completion.items(for: query("/|")!, catalog: catalog).count == 2)
        let tex = Completion.items(for: query("$\\al|$")!, catalog: catalog)
        #expect(tex.first?.title == "\\alpha")
    }

    @Test func acceptingPutsTheBlockInPlace() {
        #expect(accept("/ta|") == "| | |  |\n| --- | --- |")
        #expect(accept("앞 /ta|") == "앞\n| | |  |\n| --- | --- |")
        #expect(accept("> [!no|]") { $0.first { $0.title == "note" } } == "> [!note] |")
        #expect(accept("```py|") == "```python\n|\n```")
        #expect(accept("```py|\nx\n```") == "```python|\nx\n```")
        #expect(accept("$\\fr|$") { $0.first { $0.title == "\\frac" } } == "$\\frac{|}{}$")
        #expect(accept("$$\n\\begin{pm|}\n$$") == "$$\n\\begin{pmatrix}\n|\n\\end{pmatrix}\n$$")
        #expect(accept("$\\begin{pm|}$") == "$\\begin{pmatrix} | \\end{pmatrix}$")
        #expect(accept("값 mk|") == "값 $|$")
    }

    @Test func returnIsALineBreakUnderAMenuNobodyAskedFor() {
        #expect(query("```|")?.takesReturn == false)
        #expect(query("```py|")?.takesReturn == true)
        #expect(query("값 mk|")?.takesReturn == false)
        #expect(query("/|")?.takesReturn == true)
    }

    @Test func snippetsSharingATriggerKeepDistinctIDs() {
        var catalog = catalog
        catalog.snippets += [Snippet(trigger: "mk", body: "$$$1$$", inMath: false)]
        let items = Completion.items(for: query("값 mk|")!, catalog: catalog)
        #expect(items.count == 2)
        #expect(Set(items.map(\.id)).count == 2)
    }

    @Test func everyTeXCommandIsOfferedOnce() {
        let names = TeXCommands.all.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(TeXCommands.all.first { $0.name == "frac" }?.sample == "\\frac{a}{b}")
    }
}

struct SnippetTests {
    @Test func caretGoesToTheFirstMark() {
        #expect(Snippet(trigger: "", body: "\\frac{$1}{$2}", inMath: true).expanded == ("\\frac{}{}", 6))
        #expect(Snippet(trigger: "", body: "$$1$", inMath: false).expanded == ("$$", 1))
        #expect(Snippet(trigger: "", body: "\\alpha", inMath: true).expanded == ("\\alpha", 6))
        #expect(Snippet(trigger: "", body: "a$0b$2c$1", inMath: false).expanded == ("abc", 3))
    }
}
