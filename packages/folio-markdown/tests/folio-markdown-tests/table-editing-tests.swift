@testable import FolioMarkdown
import Foundation
import PropertyBased
import Testing

/// Table edits on the source, with `‸` marking the caret since `|` is the table's.
struct TableEditingTests {
    /// The text with the caret marks taken out, and the selection they marked.
    static func marked(_ text: String) -> (NSString, NSRange) {
        let ns = text as NSString
        let first = ns.range(of: "‸").location
        let stripped = ns.replacingOccurrences(of: "‸", with: "") as NSString
        let second = (ns.replacingCharacters(in: NSRange(location: first, length: 1), with: "") as NSString).range(of: "‸").location
        return (stripped, NSRange(location: first, length: second == NSNotFound ? 0 : second - first))
    }

    /// The text after `command`, with `‸` where the caret is left.
    static func run(_ command: TableCommand, _ text: String) -> String? {
        let (ns, selection) = marked(text)
        guard let edit = TableEditing.edit(command, in: ns, selection: selection) else { return nil }
        let out = edit.applied(to: ns) as NSString
        return out.replacingCharacters(in: NSRange(location: edit.caret, length: 0), with: "‸")
    }

    static let table = "앞 문단\n\n| 이름 | 점수 |\n|---|:-:|\n| 가‸ | 1 |\n| b | 2 |\n\n뒤 문단"

    @Test func aRowGoesBelowAndThePipesLineUp() {
        #expect(Self.run(.rowBelow, Self.table) == "앞 문단\n\n| 이름 | 점수 |\n| ---- | :--: |\n| 가   | 1    |\n| ‸     |      |\n| b    | 2    |\n\n뒤 문단")
    }

    @Test func columnsGoEitherSideAndKeepTheirAlignment() {
        #expect(Self.run(.columnLeft, Self.table) == "앞 문단\n\n|     | 이름 | 점수 |\n| --- | ---- | :--: |\n| ‸    | 가   | 1    |\n|     | b    | 2    |\n\n뒤 문단")
        #expect(Self.run(.columnRight, Self.table) == "앞 문단\n\n| 이름 |     | 점수 |\n| ---- | --- | :--: |\n| 가   | ‸    | 1    |\n| b    |     | 2    |\n\n뒤 문단")
    }

    @Test func rowsAndColumnsMoveAndGoAway() {
        #expect(Self.run(.moveRowDown, Self.table) == "앞 문단\n\n| 이름 | 점수 |\n| ---- | :--: |\n| b    | 2    |\n| 가‸   | 1    |\n\n뒤 문단")
        #expect(Self.run(.moveColumnRight, Self.table) == "앞 문단\n\n| 점수 | 이름 |\n| :--: | ---- |\n| 1    | 가‸   |\n| 2    | b    |\n\n뒤 문단")
        #expect(Self.run(.moveColumnLeft, Self.table) == nil)
        #expect(Self.run(.deleteRow, Self.table) == "앞 문단\n\n| 이름 | 점수 |\n| ---- | :--: |\n| b‸    | 2    |\n\n뒤 문단")
        #expect(Self.run(.deleteColumn, Self.table) == "앞 문단\n\n| 점수 |\n| :--: |\n| 1‸    |\n| 2    |\n\n뒤 문단")
    }

    /// The header is the first row of a GFM table, whatever is moved there.
    @Test func aRowMovedToTheTopIsTheHeader() {
        #expect(Self.run(.moveRowUp, "| a | b |\n|---|---|\n| ‸1 | 2 |") == "| 1‸   | 2   |\n| --- | --- |\n| a   | b   |")
        #expect(Self.run(.deleteRow, "| a‸ | b |\n|---|---|\n| 1 | 2 |") == "| 1‸   | 2   |\n| --- | --- |")
        #expect(Self.run(.deleteRow, "| a‸ | b |\n|---|---|") == nil)
    }

    @Test func formatLinesUpPipesAndEscapesThem() {
        #expect(Self.run(.format, "|a|b \\| c|\n|-|-:|\n|‸x||") == "| a   | b \\| c |\n| --- | -----: |\n| x‸   |        |")
    }

    @Test func aTableInAQuoteKeepsItsMarks() {
        #expect(Self.run(.rowBelow, "> | a |\n> |---|\n> | ‸1 |") == "> | a   |\n> | --- |\n> | 1   |\n> | ‸    |")
    }

    @Test func noTableNoCommand() {
        #expect(Self.run(.rowBelow, "그냥 ‸문단") == nil)
        #expect(Self.run(.rowBelow, "```\n| a |\n|---|\n| ‸1 |\n```") == nil)
        // Blank lines after a table, in a quote or a list item too, are not in it.
        #expect(Self.run(.rowBelow, "| a | b |\n|---|---|\n| 1 | 2 |\n‸\n뒤") == nil)
        #expect(Self.run(.rowBelow, "| a | b |\n|---|---|\n| 1 | 2 |\n\n‸") == nil)
        #expect(Self.run(.rowBelow, "> | a | b |\n> |---|---|\n> | 1 | 2 |\n>‸\n> 뒤") == nil)
        #expect(Self.run(.rowBelow, "- | a | b |\n  |---|---|\n  | 1 | 2 |\n‸\n  뒤") == nil)
        #expect(Self.run(.rowBelow, "- | a | b |\n  |---|---|\n  | 1 | 2 |\n  ‸\n- 둘") == nil)
    }

    /// A `cb-table` is drawn by the preview but not edited.
    @Test func aCBTableGetsNoCommands() {
        let cb = "```cb-table\n{\"rows\": [{\"header\": true, \"cells\": [{\"text\": \"a‸\"}]}, {\"cells\": [{\"text\": \"1\"}]}]}\n```"
        #expect(TableCommand.allCases.allSatisfy { Self.run($0, cb) == nil })
    }

    @Test func displayWidthCountsWideLettersTwice() {
        #expect(DisplayWidth.of("abc") == 3)
        #expect(DisplayWidth.of("이름") == 4)
        #expect(DisplayWidth.of("e\u{301}") == 1)
    }
}

/// What every table edit keeps, on random tables and random runs of edits.
struct TablePropertyTests {
    static let words = ["", "a", "가나", "x \\| y", "**b**", "$x$"]
    static let commands = TableCommand.allCases

    static func gfm(rows: Int, columns: Int, words: [Int]) -> String {
        func row(_ r: Int) -> String {
            "| " + (0..<columns).map { c in Self.words[words[(r * columns + c) % words.count]] }.joined(separator: " | ") + " |"
        }
        return ([row(0), "|" + String(repeating: "---|", count: columns)] + (1..<rows).map(row)).joined(separator: "\n")
    }

    static func texts(_ grid: TableGrid) -> [String] {
        grid.rows.flatMap { $0 }.sorted()
    }

    @Test func everyEditLeavesATableThatReadsBackAsItWasWritten() async {
        await propertyCheck(input: Gen.int(in: 2...4), Gen.int(in: 1...4), Gen.int(in: 0...5).array(of: 16), Gen.int(in: 0...10).array(of: 1...8)) { rows, columns, words, steps in
            var text = ("앞\n\n" + Self.gfm(rows: rows, columns: columns, words: words) + "\n\n뒤") as NSString
            var caret = text.range(of: "| ", options: [], range: NSRange(location: 3, length: text.length - 3)).location + 2
            for step in steps {
                let command = Self.commands[step % Self.commands.count]
                guard let before = TableEditing.table(in: text, selection: NSRange(location: caret, length: 0)) else {
                    Issue.record("no table at \(caret) in \(text)")
                    return
                }
                guard let edit = before.edit(command) else { continue }
                let next = edit.applied(to: text) as NSString
                guard let after = TableEditing.table(in: next, selection: NSRange(location: edit.caret, length: 0)) else {
                    Issue.record("\(command) left no table at the caret: \(next)")
                    return
                }
                let (a, b) = (before.grid, after.grid)
                #expect(b.rows.allSatisfy { $0.count == b.width }, "\(command): \(next)")
                switch command {
                case .rowAbove, .rowBelow: #expect(b.height == a.height + 1 && b.width == a.width)
                case .columnLeft, .columnRight: #expect(b.width == a.width + 1 && b.height == a.height)
                case .deleteRow: #expect(b.height == a.height - 1 && b.width == a.width)
                case .deleteColumn: #expect(b.width == a.width - 1 && b.height == a.height)
                case .moveRowUp, .moveRowDown, .moveColumnLeft, .moveColumnRight, .format:
                    #expect(b.width == a.width && b.height == a.height && Self.texts(a) == Self.texts(b), "\(command): \(text) → \(next)")
                }
                // Written as the editor writes it, the table is already formatted.
                if let again = after.edit(.format) { #expect(again.applied(to: next) == next as String, "\(command): \(next)") }
                #expect(next.hasPrefix("앞\n\n") && next.hasSuffix("\n\n뒤"))
                text = next
                caret = edit.caret
            }
        }
    }
}
