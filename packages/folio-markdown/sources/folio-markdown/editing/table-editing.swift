import Foundation
import Markdown

/// What the edit view can do to the table the caret is in. Each one rewrites the table's source.
public enum TableCommand: String, CaseIterable, Sendable {
    case rowAbove, rowBelow, columnLeft, columnRight
    case deleteRow, deleteColumn
    case moveRowUp, moveRowDown, moveColumnLeft, moveColumnRight
    /// The cells the selection runs across become one.
    case merge
    case mergeRight, mergeDown, unmerge
    /// Lines the pipes up (GFM), or lays the JSON out a row to a line (`cb-table`).
    case format
}

/// Table edits as changes to the markdown source, for the Mac and iPad edit views alike. A GFM table stays GFM, its
/// pipes lined up after every edit; merging cells turns it into a `cb-table`, the only table that can hold them, and
/// splitting the last merged cell turns it back when nothing else (widths, cells of several lines) needs the JSON.
public enum TableEditing {
    /// The table the selection starts in, or nil outside one.
    public static func table(in text: NSString, selection: NSRange) -> TableSource? {
        TableSource(text, selection)
    }

    public static func edit(_ command: TableCommand, in text: NSString, selection: NSRange) -> SourceEditing.Edit? {
        table(in: text, selection: selection)?.edit(command)
    }
}

/// A table found in the source: its grid, where it is, and the cells the selection starts and ends in.
public struct TableSource {
    public enum Kind: Sendable { case gfm, cbTable }

    public let kind: Kind
    public let grid: TableGrid
    /// The slots the selection starts and ends in.
    public let start: (row: Int, column: Int)
    public let end: (row: Int, column: Int)
    let text: NSString
    /// The table's lines, fences included, without the last line break.
    let block: NSRange
    /// What stands before the table on its first line and on the rest (a quote's `> `, a list item's indent).
    let firstPrefix: String
    let restPrefix: String
    let fences: (open: String, close: String)?

    // MARK: Finding

    init?(_ text: NSString, _ selection: NSRange) {
        let string = text as String
        let lines = Self.lines(text)
        let protected = MathProtection.protectMapped(string)
        let protectedLines = protected.text.split(separator: "\n", omittingEmptySubsequences: false)
        let document = Document(parsing: protected.text)
        let caretLine = Self.line(of: selection.location, in: lines)
        let endLine = Self.line(of: NSMaxRange(selection), in: lines)

        // Lines of the protected text, 1-based, to the source's, 0-based.
        func source(_ line: Int) -> Int? {
            guard line >= 1, line <= protected.origin.count else { return nil }
            return protected.origin[line - 1] - 1
        }
        var found: (node: Markup, first: Int, last: Int, column: Int)?
        func walk(_ node: Markup) {
            guard found == nil else { return }
            if node is Markdown.Table || (node as? CodeBlock)?.language == CBTable.language,
               let range = node.range, let first = source(range.lowerBound.line), let last = source(range.upperBound.line),
               first <= caretLine, caretLine <= last {
                // The column is in UTF-8 bytes of the protected line; what's before it is the same in the source.
                let line = protectedLines[range.lowerBound.line - 1]
                let bytes = min(range.lowerBound.column - 1, line.utf8.count)
                let column = String(line.utf8.prefix(bytes)).map { $0.utf16.count } ?? 0
                found = (node, first, last, column)
                return
            }
            for child in node.children { walk(child) }
        }
        walk(document)
        guard let found else { return nil }

        var last = found.last
        // A table's range can run on over blank lines after it.
        while last > found.first, text.substring(with: lines[last]).trimmingCharacters(in: .whitespaces).isEmpty { last -= 1 }
        let first = lines[found.first]
        let firstPrefix = text.substring(with: NSRange(location: first.location, length: min(found.column, first.length)))
        self.firstPrefix = firstPrefix
        let blockLines = Array(lines[found.first...last])
        let restPrefix = blockLines.count > 1 ? Self.prefix(of: text.substring(with: blockLines[1]), upTo: firstPrefix.utf16.count)
            : String(firstPrefix.map { $0 == ">" || $0.isWhitespace ? $0 : " " })
        self.restPrefix = restPrefix
        let contents = blockLines.enumerated().map { i, line -> (range: NSRange, cut: Int) in
            let cut = i == 0 ? firstPrefix.utf16.count : Self.prefix(of: text.substring(with: line), upTo: firstPrefix.utf16.count).utf16.count
            return (line, min(cut, line.length))
        }
        self.text = text
        block = NSRange(location: blockLines[0].location, length: NSMaxRange(blockLines[blockLines.count - 1]) - blockLines[0].location)
        let startLine = caretLine - found.first, stopLine = min(max(endLine, found.first), last) - found.first

        if found.node is Markdown.Table {
            kind = .gfm
            fences = nil
            let rows = contents.map { text.substring(with: NSRange(location: $0.range.location + $0.cut, length: $0.range.length - $0.cut)) }
            guard rows.count >= 2 else { return nil }
            let header = Self.split(rows[0]), delimiter = Self.split(rows[1])
            let body = rows.dropFirst(2).map(Self.split)
            let width = max(header.count, ([delimiter] + body).map(\.count).max() ?? 0)
            guard width > 0 else { return nil }
            func cells(_ split: [(text: String, range: NSRange)]) -> [TableGrid.Cell?] {
                (0..<width).map { i in TableGrid.Cell(text: i < split.count ? split[i].text : "") }
            }
            let grid = TableGrid(columns: (0..<width).map { i in TableGrid.Column(align: i < delimiter.count ? Self.alignment(delimiter[i].text) : nil) },
                                 rows: [TableGrid.Row(header: true, cells: cells(header))] + body.map { TableGrid.Row(cells: cells($0)) })
            self.grid = grid
            func slot(_ offset: Int, line: Int) -> (row: Int, column: Int) {
                let content = contents[line]
                let at = offset - content.range.location - content.cut
                let split = Self.split(rows[line])
                let column = split.firstIndex { at <= NSMaxRange($0.range) } ?? max(0, split.count - 1)
                return (max(0, line - 1), min(column, width - 1))
            }
            start = slot(selection.location, line: startLine)
            end = slot(NSMaxRange(selection), line: stopLine)
        } else {
            kind = .cbTable
            let closes = blockLines.count > 1 && Self.isFence(text.substring(with: blockLines[blockLines.count - 1]))
            fences = (text.substring(with: blockLines[0]), closes ? text.substring(with: blockLines[blockLines.count - 1]) : "\(restPrefix)```")
            // The JSON as the lines between the fences hold it, without their prefixes, and where each line starts.
            var json = ""
            var starts: [(source: Int, json: Int, length: Int)] = []
            for content in contents.dropFirst().dropLast(closes ? 1 : 0) {
                if !json.isEmpty { json += "\n" }
                let line = NSRange(location: content.range.location + content.cut, length: content.range.length - content.cut)
                starts.append((line.location, json.utf16.count, line.length))
                json += text.substring(with: line)
            }
            guard let node = JSONNode.parse(json), let (grid, places) = Self.grid(node) else { return nil }
            self.grid = grid
            func slot(_ offset: Int) -> (row: Int, column: Int) {
                guard let line = starts.last(where: { $0.source <= offset }) else { return (0, 0) }
                let at = line.json + min(max(0, offset - line.source), line.length)
                return places.first { NSLocationInRange(at, $0.range) || NSMaxRange($0.range) == at }?.slot
                    ?? places.first { $0.row && NSLocationInRange(at, $0.range) }?.slot ?? (0, 0)
            }
            start = slot(selection.location)
            end = slot(NSMaxRange(selection))
        }
    }

    // MARK: Editing

    /// The source with `command` done, the caret in the cell it leaves you in; nil when it can't be done here (a move
    /// past the edge or through a merged cell, the last row, a cell that isn't merged).
    public func edit(_ command: TableCommand) -> SourceEditing.Edit? {
        var grid = grid
        let (r, c) = start
        let here = grid.rect(r, c)
        var target = (row: r, column: c)
        switch command {
        case .rowAbove:
            grid.insertRow(at: here.rows.lowerBound)
            target = (here.rows.lowerBound, c)
        case .rowBelow:
            grid.insertRow(at: here.rows.upperBound + 1)
            target = (here.rows.upperBound + 1, c)
        case .columnLeft:
            grid.insertColumn(at: here.columns.lowerBound)
            target = (r, here.columns.lowerBound)
        case .columnRight:
            grid.insertColumn(at: here.columns.upperBound + 1)
            target = (r, here.columns.upperBound + 1)
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
        case .merge:
            let rect = grid.closed(TableGrid.Rect(rows: min(r, end.row)...max(r, end.row), columns: min(c, end.column)...max(c, end.column)))
            guard grid.merge(rect) else { return nil }
            target = (rect.rows.lowerBound, rect.columns.lowerBound)
        case .mergeRight:
            let next = here.columns.upperBound + 1
            guard next < grid.width else { return nil }
            let other = grid.rect(here.rows.lowerBound, next)
            guard other.rows == here.rows, grid.merge(TableGrid.Rect(rows: here.rows, columns: here.columns.lowerBound...other.columns.upperBound)) else { return nil }
            target = (here.rows.lowerBound, here.columns.lowerBound)
        case .mergeDown:
            let next = here.rows.upperBound + 1
            guard next < grid.height else { return nil }
            let other = grid.rect(next, here.columns.lowerBound)
            guard other.columns == here.columns, grid.merge(TableGrid.Rect(rows: here.rows.lowerBound...other.rows.upperBound, columns: here.columns)) else { return nil }
            target = (here.rows.lowerBound, here.columns.lowerBound)
        case .unmerge:
            guard grid.unmerge(r, c) else { return nil }
            target = (here.rows.lowerBound, here.columns.lowerBound)
        case .format:
            break
        }

        // A GFM table's first row is its header, whatever moved there.
        if kind == .gfm {
            for i in grid.rows.indices { grid.rows[i].header = i == 0 }
        }
        let gfm = kind == .gfm ? !grid.hasMerged : (self.grid.hasMerged && Self.fitsGFM(grid))
        let written = gfm ? Self.gfm(grid, first: firstPrefix, rest: restPrefix)
            : Self.cbTable(grid, open: fences?.open ?? "\(firstPrefix)```\(CBTable.language)", close: fences?.close ?? "\(restPrefix)```", prefix: restPrefix)
        let origin = grid.origin(min(target.row, grid.height - 1), min(target.column, grid.width - 1))
        let caret = block.location + (written.cells[origin.row][origin.column].map(NSMaxRange) ?? 0)
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

    /// Whether GFM can hold the table as it is: one header row on top, single-line cells, nothing merged, no widths
    /// or fields only the JSON has.
    static func fitsGFM(_ grid: TableGrid) -> Bool {
        guard grid.height >= 1, grid.width >= 1, !grid.hasMerged, grid.headerColumn != true, grid.extra.isEmpty,
              grid.columns.allSatisfy({ $0.isPlain && ($0.align == nil || CBTable.alignments.contains($0.align!)) }) else { return false }
        return grid.rows.enumerated().allSatisfy { i, row in
            row.header == (i == 0) && row.extra.isEmpty && row.cells.allSatisfy { $0.map { $0.extra.isEmpty && !$0.text.contains("\n") } ?? false }
        }
    }

    /// Pipes inside a cell's text escaped, as GFM needs them; ones already escaped stay as they are.
    static func escapePipes(_ text: String) -> String {
        var out = ""
        var escaped = false
        for ch in text {
            if ch == "|", !escaped { out.append("\\") }
            out.append(ch)
            escaped = ch == "\\" && !escaped
        }
        return out
    }

    /// The table with its pipes lined up, and where each cell's text is in it.
    static func gfm(_ grid: TableGrid, first: String, rest: String) -> (text: String, cells: [[NSRange?]]) {
        let texts = grid.rows.map { $0.cells.map { escapePipes($0?.text ?? "") } }
        let widths = (0..<grid.width).map { c in max(3, texts.map { DisplayWidth.of($0[c]) }.max() ?? 0) }
        var out = ""
        var cells: [[NSRange?]] = []
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
            switch grid.columns[c].align {
            case "left": return ":" + String(repeating: "-", count: w - 1)
            case "right": return String(repeating: "-", count: w - 1) + ":"
            case "center": return ":" + String(repeating: "-", count: w - 2) + ":"
            default: return String(repeating: "-", count: w)
            }
        })
        for row in texts.dropFirst() { cells.append(line(rest, row)) }
        return (out, cells)
    }

    // MARK: cb-table

    /// The grid a `cb-table`'s JSON lays out, as a browser lays out its HTML: each cell in the next slot its row has
    /// free, spans cut short at the table's edge or where another cell is. Also where each cell and row was written.
    static func grid(_ node: JSONNode) -> (TableGrid, [(range: NSRange, slot: (row: Int, column: Int), row: Bool)])? {
        guard let rowNodes = node["rows"]?.items, !rowNodes.isEmpty else { return nil }
        let height = rowNodes.count
        var slots: [[TableGrid.Cell??]] = Array(repeating: [], count: height)
        var places: [(range: NSRange, slot: (row: Int, column: Int), row: Bool)] = []
        func taken(_ r: Int, _ c: Int) -> Bool { c < slots[r].count && slots[r][c] != nil }
        func put(_ r: Int, _ c: Int, _ value: TableGrid.Cell?) {
            while slots[r].count <= c { slots[r].append(nil) }
            slots[r][c] = .some(value)
        }
        var rows: [TableGrid.Row] = []
        for (r, rowNode) in rowNodes.enumerated() {
            var row = TableGrid.Row(header: rowNode["header"]?.bool ?? false, cells: [])
            row.extra = rowNode.members?.filter { !["header", "cells"].contains($0.key) } ?? []
            rows.append(row)
            var c = 0
            var first: Int?
            for cellNode in rowNode["cells"]?.items ?? [] {
                while taken(r, c) { c += 1 }
                let rowspan = min(max(1, Int(cellNode["rowspan"]?.number ?? 1)), height - r)
                var colspan = max(1, Int(cellNode["colspan"]?.number ?? 1))
                var k = 1
                while k < colspan, !(r..<(r + rowspan)).contains(where: { taken($0, c + k) }) { k += 1 }
                colspan = k
                var cell = TableGrid.Cell(text: cellNode["text"]?.string ?? "", colspan: colspan, rowspan: rowspan)
                cell.extra = cellNode.members?.filter { !["text", "colspan", "rowspan"].contains($0.key) } ?? []
                for rr in r..<(r + rowspan) {
                    for cc in c..<(c + colspan) { put(rr, cc, rr == r && cc == c ? cell : nil) }
                }
                places.append((cellNode.range, (r, c), false))
                first = first ?? c
                c += colspan
            }
            places.append((rowNode.range, (r, first ?? 0), true))
        }
        let columnNodes = node["columns"]?.items ?? []
        let width = max(columnNodes.count, slots.map(\.count).max() ?? 0)
        guard width > 0 else { return nil }
        for r in 0..<height {
            rows[r].cells = (0..<width).map { c in c < slots[r].count ? slots[r][c] ?? TableGrid.Cell() : TableGrid.Cell() }
        }
        let columns = (0..<width).map { i -> TableGrid.Column in
            guard i < columnNodes.count else { return TableGrid.Column() }
            var column = TableGrid.Column(width: columnNodes[i]["width"]?.number, align: columnNodes[i]["align"]?.string)
            column.extra = columnNodes[i].members?.filter { !["width", "align"].contains($0.key) } ?? []
            return column
        }
        var grid = TableGrid(columns: columns, rows: rows, headerColumn: node["headerColumn"]?.bool)
        grid.extra = node.members?.filter { !["columns", "rows", "headerColumn"].contains($0.key) } ?? []
        return (grid, places)
    }

    /// The `cb-table` block, a row to a line, and where each cell's text is in it.
    static func cbTable(_ grid: TableGrid, open: String, close: String, prefix: String) -> (text: String, cells: [[NSRange?]]) {
        var out = open + "\n" + prefix + "{\n"
        var cells: [[NSRange?]] = Array(repeating: Array(repeating: nil, count: grid.width), count: grid.height)
        var parts: [String] = []
        if !grid.columns.allSatisfy({ $0.isPlain && $0.align == nil }) {
            let columns = grid.columns.map { column -> String in
                var members: [JSONNode.Member] = []
                if let w = column.width { members.append(.init(key: "width", value: JSONNode(.number(JSONNode.number(w))))) }
                if let a = column.align { members.append(.init(key: "align", value: JSONNode(.string(a)))) }
                return JSONNode(.object(members + column.extra)).text
            }
            parts.append("\"columns\": [" + columns.joined(separator: ", ") + "]")
        }
        if let h = grid.headerColumn { parts.append("\"headerColumn\": \(h)") }
        for part in parts { out += prefix + "  " + part + ",\n" }
        out += prefix + "  \"rows\": [\n"
        for (r, row) in grid.rows.enumerated() {
            out += prefix + "    {" + (row.header ? "\"header\": true, " : "") + "\"cells\": ["
            var first = true
            for (c, slot) in row.cells.enumerated() {
                guard let cell = slot else { continue }
                if !first { out += ", " }
                first = false
                out += "{\"text\": "
                let quoted = JSONNode.quoted(cell.text)
                // The caret goes at the text's end, inside its closing quote.
                cells[r][c] = NSRange(location: out.utf16.count + 1, length: quoted.utf16.count - 2)
                out += quoted
                if cell.colspan > 1 { out += ", \"colspan\": \(cell.colspan)" }
                if cell.rowspan > 1 { out += ", \"rowspan\": \(cell.rowspan)" }
                for m in cell.extra { out += ", " + JSONNode.quoted(m.key) + ": " + m.value.text }
                out += "}"
            }
            out += "]"
            for m in row.extra { out += ", " + JSONNode.quoted(m.key) + ": " + m.value.text }
            out += "}" + (r < grid.height - 1 ? "," : "") + "\n"
        }
        out += prefix + "  ]"
        for m in grid.extra { out += ",\n" + prefix + "  " + JSONNode.quoted(m.key) + ": " + m.value.text }
        out += "\n" + prefix + "}\n" + close
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

    static func isFence(_ line: String) -> Bool {
        line.wholeMatch(of: #/[ \t>]*(`{3,}|~{3,})[ \t]*/#) != nil
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
