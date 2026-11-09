import Foundation
import Markdown

/// What the edit view can do to the GFM table the caret is in. Each one rewrites the table's source.
public enum TableCommand: String, CaseIterable, Sendable {
    case rowAbove, rowBelow, columnLeft, columnRight
    case deleteRow, deleteColumn
    case moveRowUp, moveRowDown, moveColumnLeft, moveColumnRight
    /// Lines the pipes up, as every other command also does.
    case format
}

/// Table edits as changes to the markdown source, for the Mac and iPad edit views alike. Only GFM pipe tables: a
/// `cb-table` is drawn by the preview but not edited (#39).
public enum TableEditing {
    /// The table the selection starts in, or nil outside one.
    public static func table(in text: NSString, selection: NSRange) -> TableSource? {
        TableSource(text, selection)
    }

    public static func edit(_ command: TableCommand, in text: NSString, selection: NSRange) -> SourceEditing.Edit? {
        table(in: text, selection: selection)?.edit(command)
    }
}

/// A GFM table found in the source: its grid, where it is, and the cell the selection starts in.
public struct TableSource {
    public let grid: TableGrid
    public let cell: (row: Int, column: Int)
    let text: NSString
    /// The table's lines, without the last line break.
    let block: NSRange
    /// What stands before the table on its first line and on the rest (a quote's `> `, a list item's indent).
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

        // Lines of the protected text, 1-based, to the source's, 0-based.
        func source(_ line: Int) -> Int? {
            guard line >= 1, line <= protected.origin.count else { return nil }
            return protected.origin[line - 1] - 1
        }
        var found: (first: Int, last: Int, column: Int)?
        func walk(_ node: Markup) {
            guard found == nil else { return }
            if node is Markdown.Table, let range = node.range, let first = source(range.lowerBound.line), let last = source(range.upperBound.line),
               first <= caretLine, caretLine <= last {
                // The column is in UTF-8 bytes of the protected line; what's before it is the same in the source.
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
        // A table's range could run on over blank lines after it.
        while last > found.first, text.substring(with: lines[last]).trimmingCharacters(in: .whitespaces).isEmpty { last -= 1 }
        // A caret on such a line is outside the table; its rows below would not reach that far.
        guard caretLine <= last else { return nil }
        let first = lines[found.first]
        let firstPrefix = text.substring(with: NSRange(location: first.location, length: min(found.column, first.length)))
        self.firstPrefix = firstPrefix
        let blockLines = Array(lines[found.first...last])
        restPrefix = blockLines.count > 1 ? Self.prefix(of: text.substring(with: blockLines[1]), upTo: firstPrefix.utf16.count)
            : String(firstPrefix.map { $0 == ">" || $0.isWhitespace ? $0 : " " })
        let contents = blockLines.enumerated().map { i, line -> (range: NSRange, cut: Int) in
            let cut = i == 0 ? firstPrefix.utf16.count : Self.prefix(of: text.substring(with: line), upTo: firstPrefix.utf16.count).utf16.count
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
        grid = TableGrid(alignments: (0..<width).map { i in i < delimiter.count ? Self.alignment(delimiter[i].text) : nil },
                         rows: [cells(header)] + body.map(cells))
        // The delimiter row holds no cell; a caret on it is in the header.
        let line = caretLine - found.first
        let content = contents[line]
        let at = selection.location - content.range.location - content.cut
        let split = Self.split(rows[line])
        let column = split.firstIndex { at <= NSMaxRange($0.range) } ?? max(0, split.count - 1)
        cell = (max(0, line - 1), min(column, width - 1))
    }

    // MARK: Editing

    /// The source with `command` done, the caret at the end of the cell it leaves you in; nil when it can't be done
    /// here (a move past the edge, deleting the last row or column).
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

    /// A row's cells between unescaped pipes, trimmed, with the range of each between its pipes.
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
        // What follows the last pipe is a cell only if it holds something.
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

    /// Where a `[[…]]` starting at `i` ends, past its `]]`. Its `|` is the link's, not a cell's, as Obsidian and the
    /// preview read it (`MathProtection`), so the link's own `[[target|alias]]` keeps the row's cells whole.
    static func wikiLinkEnd(_ units: [UInt16], _ i: Int) -> Int? {
        guard i + 1 < units.count, units[i] == 0x5B, units[i + 1] == 0x5B else { return nil }
        var j = i + 2
        while j + 1 < units.count {
            if units[j] == 0x5D { return units[j + 1] == 0x5D && j > i + 2 ? j + 2 : nil }
            j += 1
        }
        return nil
    }

    /// Pipes inside a cell's text escaped, as GFM needs them; ones already escaped, and a link's, stay as they are.
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

    /// The table with its pipes lined up, and where each cell's text is in it.
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
        _ = line(rest, (0..<grid.width).map { c in
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

    /// A line's quote marks and indent, no longer than the table's first line has.
    static func prefix(of line: String, upTo length: Int) -> String {
        var out = ""
        for ch in line {
            guard ch == " " || ch == "\t" || ch == ">", out.utf16.count < length else { break }
            out.append(ch)
        }
        return out
    }
}

/// How many columns text takes in a monospaced font: Hangul, CJK and emoji two, combining marks none. Pipes are lined
/// up by it, so a table of Korean lines up in the edit view as one of English does.
public enum DisplayWidth {
    public static func of(_ text: String) -> Int {
        text.reduce(0) { $0 + of($1) }
    }

    static func of(_ ch: Character) -> Int {
        var zero = true
        for s in ch.unicodeScalars {
            let v = s.value
            if wide(v) { return 2 }
            if !(0x0300...0x036F).contains(v), !(0x200B...0x200F).contains(v), !(0xFE00...0xFE0F).contains(v),
               !(0x1160...0x11FF).contains(v), s.properties.generalCategory != .nonspacingMark {
                zero = false
            }
        }
        return zero ? 0 : 1
    }

    static func wide(_ v: UInt32) -> Bool {
        (0x1100...0x115F).contains(v) || (0x2E80...0x303E).contains(v) || (0x3041...0x33FF).contains(v)
            || (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0xA000...0xA4CF).contains(v)
            || (0xA960...0xA97F).contains(v) || (0xAC00...0xD7A3).contains(v) || (0xF900...0xFAFF).contains(v)
            || (0xFE30...0xFE4F).contains(v) || (0xFF00...0xFF60).contains(v) || (0xFFE0...0xFFE6).contains(v)
            || (0x1F300...0x1F64F).contains(v) || (0x1F900...0x1F9FF).contains(v) || (0x20000...0x3FFFD).contains(v)
    }
}
