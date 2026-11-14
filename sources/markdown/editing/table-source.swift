import Foundation
import Markdown

public struct TableSource {
    public let grid: TableGrid
    public let cell: (row: Int, column: Int)
    let text: NSString
    let block: NSRange
    let firstPrefix: String
    let restPrefix: String

    // MARK: Finding

    init?(_ text: NSString, _ selection: NSRange) {
        let string = text as String
        let lines = Self.lines(text)
        let protected = MathProtection.protectMapped(string)
        let protectedLines = protected.text.split(separator: "\n", omittingEmptySubsequences: false)
        let document = Document(parsing: protected.text)
        let caretLine = Self.line(of: selection.location, in: lines)

        func source(_ line: Int) -> Int? {
            guard line >= 1, line <= protected.origin.count else { return nil }
            return protected.origin[line - 1] - 1
        }

        var found: (first: Int, last: Int, column: Int)?
        func walk(_ node: Markup) {
            guard found == nil else { return }
            if node is Markdown.Table, let range = node.range, let first = source(range.lowerBound.line),
                let last = source(range.upperBound.line),
                first <= caretLine, caretLine <= last
            {
                // 열은 보호한 줄의 UTF-8 바이트 단위이고, 그 앞의 글은 원문과 같다.
                let line = protectedLines[range.lowerBound.line - 1]
                let bytes = min(range.lowerBound.column - 1, line.utf8.count)
                let column = String(line.utf8.prefix(bytes)).map { $0.utf16.count } ?? 0
                found = (first, last, column)
                return
            }
            for child in node.children { walk(child) }
        }
        walk(document)
        guard let found else { return nil }

        var last = found.last
        while last > found.first, text.substring(with: lines[last]).trimmingCharacters(in: .whitespaces).isEmpty { last -= 1 }
        guard caretLine <= last else { return nil }
        let first = lines[found.first]
        let firstPrefix = text.substring(with: NSRange(location: first.location, length: min(found.column, first.length)))
        self.firstPrefix = firstPrefix
        let blockLines = Array(lines[found.first...last])
        restPrefix =
            blockLines.count > 1
            ? Self.prefix(of: text.substring(with: blockLines[1]), upTo: firstPrefix.utf16.count)
            : String(firstPrefix.map { $0 == ">" || $0.isWhitespace ? $0 : " " })
        let contents = blockLines.enumerated().map { i, line -> (range: NSRange, cut: Int) in
            let cut =
                i == 0 ? firstPrefix.utf16.count : Self.prefix(of: text.substring(with: line), upTo: firstPrefix.utf16.count).utf16.count
            return (line, min(cut, line.length))
        }
        self.text = text
        block = NSRange(location: blockLines[0].location, length: NSMaxRange(blockLines[blockLines.count - 1]) - blockLines[0].location)

        let rows = contents.map { text.substring(with: NSRange(location: $0.range.location + $0.cut, length: $0.range.length - $0.cut)) }
        guard rows.count >= 2 else { return nil }
        let header = Self.split(rows[0]), delimiter = Self.split(rows[1])
        let body = rows.dropFirst(2).map(Self.split)
        let width = max(header.count, ([delimiter] + body).map(\.count).max() ?? 0)
        guard width > 0 else { return nil }
        func cells(_ split: [(text: String, range: NSRange)]) -> [String] {
            (0..<width).map { i in i < split.count ? split[i].text : "" }
        }
        grid = TableGrid(
            alignments: (0..<width).map { i in i < delimiter.count ? Self.alignment(delimiter[i].text) : nil },
            rows: [cells(header)] + body.map(cells))

        let line = caretLine - found.first
        let content = contents[line]
        let at = selection.location - content.range.location - content.cut
        let split = Self.split(rows[line])
        let column = split.firstIndex { at <= NSMaxRange($0.range) } ?? max(0, split.count - 1)
        cell = (max(0, line - 1), min(column, width - 1))
    }

    // MARK: Editing

    public func edit(_ command: TableCommand) -> SourceEditing.Edit? {
        var grid = grid
        let (r, c) = cell
        var target = (row: r, column: c)
        switch command {
        case .rowAbove:
            grid.insertRow(at: r)
        case .rowBelow:
            grid.insertRow(at: r + 1)
            target = (r + 1, c)
        case .columnLeft:
            grid.insertColumn(at: c)
        case .columnRight:
            grid.insertColumn(at: c + 1)
            target = (r, c + 1)
        case .deleteRow:
            guard grid.height > 1 else { return nil }
            grid.removeRow(at: r)
            target = (min(r, grid.height - 1), c)
        case .deleteColumn:
            guard grid.width > 1 else { return nil }
            grid.removeColumn(at: c)
            target = (r, min(c, grid.width - 1))
        case .moveRowUp, .moveRowDown:
            let step = command == .moveRowUp ? -1 : 1
            guard grid.moveRow(r, by: step) else { return nil }
            target = (r + step, c)
        case .moveColumnLeft, .moveColumnRight:
            let step = command == .moveColumnLeft ? -1 : 1
            guard grid.moveColumn(c, by: step) else { return nil }
            target = (r, c + step)
        case .format:
            break
        }

        let written = Self.gfm(grid, first: firstPrefix, rest: restPrefix)
        let caret = block.location + NSMaxRange(written.cells[target.row][target.column])
        let new = text.replacingCharacters(in: block, with: written.text) as NSString
        return SourceEditing.diff(text, new, caret: caret)
    }

    // MARK: GFM

    static func split(_ line: String) -> [(text: String, range: NSRange)] {
        let units = Array(line.utf16)
        var i = 0
        while i < units.count, units[i] == 0x20 || units[i] == 0x09 { i += 1 }
        if i < units.count, units[i] == 0x7C { i += 1 }
        var out: [(String, NSRange)] = []
        var start = i
        func cell(_ from: Int, _ to: Int) {
            let s = String(utf16CodeUnits: Array(units[from..<to]), count: to - from)
            out.append((s.trimmingCharacters(in: .whitespaces), NSRange(location: from, length: to - from)))
        }
        while i < units.count {
            if units[i] == 0x5C { i += 2; continue }
            if let end = wikiLinkEnd(units, i) { i = end; continue }
            if units[i] == 0x7C {
                cell(start, i)
                start = i + 1
            }
            i += 1
        }
        i = min(i, units.count)
        let rest = String(utf16CodeUnits: Array(units[start..<i]), count: i - start)
        if !rest.trimmingCharacters(in: .whitespaces).isEmpty || out.isEmpty { cell(start, i) }
        return out
    }

    static func alignment(_ delimiter: String) -> String? {
        switch (delimiter.hasPrefix(":"), delimiter.hasSuffix(":") && delimiter.count > 1) {
        case (true, true): "center"
        case (true, false): "left"
        case (false, true): "right"
        default: nil
        }
    }

    // `[[...]]` 안의 `|`는 칸 구분자가 아니라 링크의 구분자다. Obsidian과 미리보기(`MathProtection`)도 이렇게 읽는다.
    static func wikiLinkEnd(_ units: [UInt16], _ i: Int) -> Int? {
        guard i + 1 < units.count, units[i] == 0x5B, units[i + 1] == 0x5B else { return nil }
        var j = i + 2
        while j + 1 < units.count {
            if units[j] == 0x5D { return units[j + 1] == 0x5D && j > i + 2 ? j + 2 : nil }
            j += 1
        }
        return nil
    }

    static func escapePipes(_ text: String) -> String {
        let units = Array(text.utf16)
        var out: [UInt16] = []
        var i = 0
        while i < units.count {
            if units[i] == 0x5C {
                out += units[i..<min(i + 2, units.count)]
                i += 2
                continue
            }
            if let end = wikiLinkEnd(units, i) {
                out += units[i..<end]
                i = end
                continue
            }
            if units[i] == 0x7C { out.append(0x5C) }
            out.append(units[i])
            i += 1
        }
        return String(utf16CodeUnits: out, count: out.count)
    }

    static func gfm(_ grid: TableGrid, first: String, rest: String) -> (text: String, cells: [[NSRange]]) {
        let texts = grid.rows.map { $0.map(escapePipes) }
        let widths = (0..<grid.width).map { c in max(3, texts.map { DisplayWidth.of($0[c]) }.max() ?? 0) }
        var out = ""
        var cells: [[NSRange]] = []
        func line(_ prefix: String, _ items: [String]) -> [NSRange] {
            if !out.isEmpty { out += "\n" }
            out += prefix + "|"
            var ranges: [NSRange] = []
            for (c, item) in items.enumerated() {
                out += " "
                ranges.append(NSRange(location: out.utf16.count, length: item.utf16.count))
                out += item + String(repeating: " ", count: max(0, widths[c] - DisplayWidth.of(item))) + " |"
            }
            return ranges
        }

        cells.append(line(first, texts[0]))
        _ = line(
            rest,
            (0..<grid.width).map { c in
                let w = widths[c]
                switch grid.alignments[c] {
                case "left": return ":" + String(repeating: "-", count: w - 1)
                case "right": return String(repeating: "-", count: w - 1) + ":"
                case "center": return ":" + String(repeating: "-", count: w - 2) + ":"
                default: return String(repeating: "-", count: w)
                }
            })
        for row in texts.dropFirst() { cells.append(line(rest, row)) }
        return (out, cells)
    }

    // MARK: Lines

    static func lines(_ text: NSString) -> [NSRange] {
        var out: [NSRange] = []
        var start = 0
        while true {
            let r = text.range(of: "\n", range: NSRange(location: start, length: text.length - start))
            if r.location == NSNotFound {
                out.append(NSRange(location: start, length: text.length - start))
                return out
            }
            out.append(NSRange(location: start, length: r.location - start))
            start = r.location + 1
        }
    }

    static func line(of offset: Int, in lines: [NSRange]) -> Int {
        lines.lastIndex { $0.location <= offset } ?? 0
    }

    static func prefix(of line: String, upTo length: Int) -> String {
        var out = ""
        for ch in line {
            guard ch == " " || ch == "\t" || ch == ">", out.utf16.count < length else { break }
            out.append(ch)
        }
        return out
    }
}
