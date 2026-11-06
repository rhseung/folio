@testable import FolioMarkdown
import Foundation
import PropertyBased
import Testing

/// Table edits on the source: a `|` in `text` marks the caret (and two, a selection), as in `EditingTests`.
struct TableEditingTests {
    /// The text with the caret marks taken out, and the selection they marked. `‸` marks it, since `|` is the table's.
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

    // MARK: Merging

    @Test func mergingTurnsTheTableIntoACBTableAndSplittingTurnsItBack() throws {
        let merged = try #require(Self.run(.mergeRight, "| a | b |\n|---|:-:|\n| ‸1 | 2 |\n| 3 | 4 |"))
        #expect(merged == """
        ```cb-table
        {
          "columns": [{}, {"align": "center"}],
          "rows": [
            {"header": true, "cells": [{"text": "a"}, {"text": "b"}]},
            {"cells": [{"text": "1\\n2‸", "colspan": 2}]},
            {"cells": [{"text": "3"}, {"text": "4"}]}
          ]
        }
        ```
        """)
        #expect(Self.run(.unmerge, merged) == "| a   | b   |\n| --- | :-: |\n| 1‸   | 2   |\n| 3   | 4   |")
    }

    /// A cb-table left with nothing GFM can't hold goes back to GFM on the next edit, not only the one that split it.
    @Test func aPlainCBTableTurnsBackOnAnyEdit() {
        let cb = "```cb-table\n{\"rows\": [{\"cells\": [{\"text\": \"x‸\"}]}, {\"header\": true, \"cells\": [{\"text\": \"a\"}]}, {\"cells\": [{\"text\": \"1\"}]}]}\n```"
        #expect(Self.run(.format, cb)?.hasPrefix("```cb-table\n") == true)
        #expect(Self.run(.deleteRow, cb) == "| a‸   |\n| --- |\n| 1   |")
    }

    @Test func aSelectionAcrossCellsMergesThemAll() {
        let out = Self.run(.merge, "| a | b | c |\n|---|---|---|\n| ‸1 | 2 | 3 |\n| 4 | 5‸ | 6 |")
        #expect(out?.contains(#"{"cells": [{"text": "1\n2\n4\n5‸", "colspan": 2, "rowspan": 2}, {"text": "3"}]},"#) == true)
        #expect(out?.contains(#"{"cells": [{"text": "6"}]}"#) == true)
    }

    @Test func mergingDownNeedsTheSameColumns() {
        let cb = "```cb-table\n{\"rows\": [{\"cells\": [{\"text\": \"a‸\", \"colspan\": 2}]}, {\"cells\": [{\"text\": \"b\"}, {\"text\": \"c\"}]}]}\n```"
        #expect(Self.run(.mergeDown, cb) == nil)
        #expect(Self.run(.mergeRight, cb) == nil)
        #expect(Self.run(.unmerge, cb)?.hasPrefix("```cb-table\n") == true)
    }

    /// A row added through a merged cell makes it taller; a column added beside it leaves it as it is.
    @Test func editsThroughAMergedCellStretchIt() throws {
        let cb = "```cb-table\n{\"columns\": [{\"width\": 120}, {}], \"rows\": [{\"cells\": [{\"text\": \"tall\", \"rowspan\": 2}, {\"text\": \"x‸\"}]}, {\"cells\": [{\"text\": \"y\"}]}]}\n```"
        let below = try #require(Self.run(.rowAbove, cb.replacingOccurrences(of: "x‸", with: "x").replacingOccurrences(of: "\"y\"", with: "\"y‸\"")))
        #expect(below.contains(#"{"cells": [{"text": "tall", "rowspan": 3}, {"text": "x"}]},"#))
        #expect(below.contains(#"{"cells": [{"text": "‸"}]},"#))
        let right = try #require(Self.run(.columnLeft, cb))
        #expect(right.contains(#""columns": [{"width": 120}, {}, {}],"#))
        #expect(right.contains(#"{"cells": [{"text": "tall", "rowspan": 2}, {"text": "‸"}, {"text": "x"}]},"#))
    }

    /// Fields the editor doesn't know stay where they were; a GFM table can't hold them, so the table stays JSON.
    @Test func unknownFieldsSurvive() throws {
        let cb = "```cb-table\n{\"caption\": \"표 1\", \"rows\": [{\"note\": 1, \"header\": true, \"cells\": [{\"text\": \"a‸\", \"colspan\": 2, \"color\": \"red\"}]}, {\"cells\": [{\"text\": \"b\"}, {\"text\": \"c\"}]}]}\n```"
        let out = try #require(Self.run(.unmerge, cb))
        #expect(out.contains(#"{"header": true, "cells": [{"text": "a‸", "color": "red"}, {"text": ""}], "note": 1},"#))
        #expect(out.contains(#""caption": "표 1""#))
    }

    @Test func theCaretFindsItsCellInTheJSON() throws {
        let (text, selection) = Self.marked("```cb-table\n{\"rows\": [{\"cells\": [{\"text\": \"a\"}, {\"text\": \"b\", \"rowspan\": 2}]},\n {\"cells\": [{\"text\": \"c‸\"}]}]}\n```")
        let table = try #require(TableEditing.table(in: text, selection: selection))
        #expect(table.kind == .cbTable)
        #expect(table.start.row == 1 && table.start.column == 0)
        #expect(table.grid.width == 2 && table.grid.height == 2 && table.grid[1, 1] == nil)
    }

    @Test func cbTableAlignmentCountsCellsMergedFromAbove() {
        let html = HTMLRenderer.render(markdown: "```cb-table\n{\"columns\": [{}, {\"align\": \"right\"}], \"rows\": [{\"cells\": [{\"text\": \"a\", \"rowspan\": 2}, {\"text\": \"b\"}]}, {\"cells\": [{\"text\": \"c\"}]}]}\n```")
        #expect(html.contains("<td class=\"after-merged\" style=\"text-align:right\"><p>c</p>"))
        #expect(html.contains("<td class=\"to-end\" rowspan=\"2\">"))
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
        grid.rows.flatMap { $0.cells.compactMap { $0?.text } }.sorted()
    }

    @Test func everyEditLeavesATableThatReadsBackAsItWasWritten() async {
        await propertyCheck(input: Gen.int(in: 2...4), Gen.int(in: 1...4), Gen.int(in: 0...5).array(of: 16), Gen.int(in: 0...14).array(of: 1...8)) { rows, columns, words, steps in
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
                #expect(b.isConsistent, "\(command): \(next)")
                #expect(after.kind == (b.hasMerged ? .cbTable : .gfm) || (after.kind == .cbTable && !TableSource.fitsGFM(b)), "\(command): \(next)")
                switch command {
                case .rowAbove, .rowBelow: #expect(b.height == a.height + 1 && b.width == a.width)
                case .columnLeft, .columnRight: #expect(b.width == a.width + 1 && b.height == a.height)
                case .deleteRow: #expect(b.height == a.height - 1 && b.width == a.width)
                case .deleteColumn: #expect(b.width == a.width - 1 && b.height == a.height)
                case .moveRowUp, .moveRowDown, .moveColumnLeft, .moveColumnRight, .format:
                    #expect(b.width == a.width && b.height == a.height && Self.texts(a) == Self.texts(b), "\(command): \(text) → \(next)")
                case .merge, .mergeRight, .mergeDown, .unmerge:
                    #expect(b.width == a.width && b.height == a.height)
                }
                // Written as the editor writes it, the table is already formatted.
                if let again = after.edit(.format) { #expect(again.applied(to: next) == next as String, "\(command): \(next)") }
                #expect(next.hasPrefix("앞\n\n") && next.hasSuffix("\n\n뒤"))
                text = next
                caret = edit.caret
            }
        }
    }

    @Test func mergingThenSplittingGivesTheCellsBack() async {
        await propertyCheck(input: Gen.int(in: 2...4), Gen.int(in: 2...4), Gen.int(in: 1...5).array(of: 16)) { rows, columns, words in
            let text = Self.gfm(rows: rows, columns: columns, words: words) as NSString
            let caret = text.range(of: "| ").location + 2
            guard let merged = TableEditing.edit(.mergeRight, in: text, selection: NSRange(location: caret, length: 0)) else {
                Issue.record("couldn't merge \(text)")
                return
            }
            let after = merged.applied(to: text) as NSString
            guard let split = TableEditing.edit(.unmerge, in: after, selection: NSRange(location: merged.caret, length: 0)) else {
                Issue.record("couldn't split \(after)")
                return
            }
            let back = split.applied(to: after) as NSString
            let format = TableEditing.edit(.format, in: text, selection: NSRange(location: caret, length: 0))!
            #expect(back as String == format.applied(to: text), "\(text) → \(after) → \(back)")
        }
    }
}
