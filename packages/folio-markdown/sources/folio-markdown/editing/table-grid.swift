import Foundation

/// A note table as a grid of slots, the same for a GFM table and a `cb-table`: each slot holds the cell that starts
/// there, or nil where a merged cell above or to the left covers it. Row and column edits work on slots, so a merged
/// cell grows or shrinks with the rows and columns it spans.
public struct TableGrid: Equatable, Sendable {
    public struct Cell: Equatable, Sendable {
        /// Markdown. In a GFM table, as written between the pipes.
        public var text: String
        public var colspan = 1
        public var rowspan = 1
        /// Fields of a `cb-table` cell the editor doesn't know, written back as they were.
        var extra: [JSONNode.Member] = []

        public init(text: String = "", colspan: Int = 1, rowspan: Int = 1) {
            self.text = text
            self.colspan = colspan
            self.rowspan = rowspan
        }

        public var merged: Bool { colspan > 1 || rowspan > 1 }
    }

    public struct Column: Equatable, Sendable {
        /// Points, as the preview draws it.
        public var width: Double?
        /// `left`, `center` or `right`; anything else is kept and drawn unaligned.
        public var align: String?
        var extra: [JSONNode.Member] = []

        public init(width: Double? = nil, align: String? = nil) {
            self.width = width
            self.align = align
        }

        var isPlain: Bool { width == nil && extra.isEmpty }
    }

    public struct Row: Equatable, Sendable {
        public var header = false
        public var cells: [Cell?]
        var extra: [JSONNode.Member] = []

        public init(header: Bool = false, cells: [Cell?]) {
            self.header = header
            self.cells = cells
        }
    }

    public var columns: [Column]
    public var rows: [Row]
    public var headerColumn: Bool?
    var extra: [JSONNode.Member] = []

    public init(columns: [Column], rows: [Row], headerColumn: Bool? = nil) {
        self.columns = columns
        self.rows = rows
        self.headerColumn = headerColumn
    }

    public var width: Int { columns.count }
    public var height: Int { rows.count }

    public struct Rect: Equatable, Sendable {
        public var rows: ClosedRange<Int>
        public var columns: ClosedRange<Int>
    }

    public subscript(row: Int, column: Int) -> Cell? {
        get { rows[row].cells[column] }
        set { rows[row].cells[column] = newValue }
    }

    /// Where the cell covering a slot starts.
    public func origin(_ row: Int, _ column: Int) -> (row: Int, column: Int) {
        for r in stride(from: row, through: 0, by: -1) {
            for c in stride(from: column, through: 0, by: -1) {
                if let cell = self[r, c], r + cell.rowspan > row, c + cell.colspan > column { return (r, c) }
            }
        }
        return (row, column)
    }

    /// The slots the cell covering a slot spans.
    public func rect(_ row: Int, _ column: Int) -> Rect {
        let o = origin(row, column)
        let cell = self[o.row, o.column] ?? Cell()
        return Rect(rows: o.row...(o.row + cell.rowspan - 1), columns: o.column...(o.column + cell.colspan - 1))
    }

    public var hasMerged: Bool { rows.contains { $0.cells.contains { $0?.merged == true } } }

    // MARK: Rows

    /// A row of empty cells at `index`; a merged cell that spans across that place spans the new row too.
    public mutating func insertRow(at index: Int) {
        var row = Row(cells: [])
        var c = 0
        while c < width {
            if index > 0, index < height {
                let o = origin(index, c)
                if o.row < index, var cell = self[o.row, o.column] {
                    cell.rowspan += 1
                    self[o.row, o.column] = cell
                    row.cells += Array(repeating: nil, count: cell.colspan)
                    c += cell.colspan
                    continue
                }
            }
            row.cells.append(Cell())
            c += 1
        }
        rows.insert(row, at: index)
    }

    /// Takes out a row. A merged cell starting in it moves down to the next row, keeping its text; one spanning it
    /// from above spans one row less.
    public mutating func removeRow(at index: Int) {
        for c in 0..<width {
            if let cell = self[index, c], cell.rowspan > 1 {
                var moved = cell
                moved.rowspan -= 1
                self[index + 1, c] = moved
            } else if self[index, c] == nil {
                let o = origin(index, c)
                if o.row < index, o.column == c, var cell = self[o.row, o.column] {
                    cell.rowspan -= 1
                    self[o.row, o.column] = cell
                }
            }
        }
        rows.remove(at: index)
    }

    /// Whether no merged cell reaches into the rows or out of them, so they can change places.
    func standsAlone(rows band: ClosedRange<Int>) -> Bool {
        for r in band {
            for c in 0..<width {
                let rect = rect(r, c)
                if rect.rows.lowerBound < band.lowerBound || rect.rows.upperBound > band.upperBound { return false }
            }
        }
        return true
    }

    public mutating func moveRow(_ index: Int, by step: Int) -> Bool {
        let other = index + step
        guard step == 1 || step == -1, rows.indices.contains(index), rows.indices.contains(other),
              standsAlone(rows: index...index), standsAlone(rows: other...other) else { return false }
        rows.swapAt(index, other)
        return true
    }

    // MARK: Columns

    public mutating func insertColumn(at index: Int) {
        var r = 0
        var cells: [Cell?] = []
        while r < height {
            if index > 0, index < width {
                let o = origin(r, index)
                if o.column < index, var cell = self[o.row, o.column] {
                    if o.row == r {
                        cell.colspan += 1
                        self[o.row, o.column] = cell
                    }
                    cells.append(nil)
                    r += 1
                    continue
                }
            }
            cells.append(Cell())
            r += 1
        }
        for r in 0..<height { rows[r].cells.insert(cells[r], at: index) }
        columns.insert(Column(), at: index)
    }

    public mutating func removeColumn(at index: Int) {
        for r in 0..<height {
            if let cell = self[r, index], cell.colspan > 1 {
                var moved = cell
                moved.colspan -= 1
                self[r, index + 1] = moved
            } else if self[r, index] == nil {
                let o = origin(r, index)
                if o.column < index, o.row == r, var cell = self[o.row, o.column] {
                    cell.colspan -= 1
                    self[o.row, o.column] = cell
                }
            }
        }
        for r in 0..<height { rows[r].cells.remove(at: index) }
        columns.remove(at: index)
    }

    func standsAlone(columns band: ClosedRange<Int>) -> Bool {
        for r in 0..<height {
            for c in band {
                let rect = rect(r, c)
                if rect.columns.lowerBound < band.lowerBound || rect.columns.upperBound > band.upperBound { return false }
            }
        }
        return true
    }

    public mutating func moveColumn(_ index: Int, by step: Int) -> Bool {
        let other = index + step
        guard step == 1 || step == -1, columns.indices.contains(index), columns.indices.contains(other),
              standsAlone(columns: index...index), standsAlone(columns: other...other) else { return false }
        for r in 0..<height { rows[r].cells.swapAt(index, other) }
        columns.swapAt(index, other)
        return true
    }

    // MARK: Merging

    /// The smallest rectangle holding `rect` that cuts through no merged cell.
    public func closed(_ rect: Rect) -> Rect {
        var out = rect
        var grew = true
        while grew {
            grew = false
            for r in out.rows {
                for c in out.columns {
                    let cell = self.rect(r, c)
                    let rows = min(out.rows.lowerBound, cell.rows.lowerBound)...max(out.rows.upperBound, cell.rows.upperBound)
                    let columns = min(out.columns.lowerBound, cell.columns.lowerBound)...max(out.columns.upperBound, cell.columns.upperBound)
                    if rows != out.rows || columns != out.columns {
                        out = Rect(rows: rows, columns: columns)
                        grew = true
                    }
                }
            }
        }
        return out
    }

    /// Makes the cells in `rect` one, its text theirs joined line by line. False when `rect` cuts through a merged
    /// cell or holds only one.
    public mutating func merge(_ rect: Rect) -> Bool {
        guard closed(rect) == rect, rect.rows.count * rect.columns.count > 1, self.rect(rect.rows.lowerBound, rect.columns.lowerBound) != rect else {
            return false
        }
        var texts: [String] = []
        for r in rect.rows {
            for c in rect.columns {
                if let cell = self[r, c], !cell.text.trimmingCharacters(in: .whitespaces).isEmpty { texts.append(cell.text) }
                if r != rect.rows.lowerBound || c != rect.columns.lowerBound { self[r, c] = nil }
            }
        }
        var top = self[rect.rows.lowerBound, rect.columns.lowerBound] ?? Cell()
        top.text = texts.joined(separator: "\n")
        top.rowspan = rect.rows.count
        top.colspan = rect.columns.count
        self[rect.rows.lowerBound, rect.columns.lowerBound] = top
        return true
    }

    /// Splits the merged cell covering a slot back into single cells, its lines handed out to them in reading order
    /// and any left over kept in the last. Merging joined the cells' texts a line each, so splitting right after gives
    /// them back, and the table can be GFM again.
    public mutating func unmerge(_ row: Int, _ column: Int) -> Bool {
        let rect = rect(row, column)
        guard rect.rows.count * rect.columns.count > 1, var top = self[rect.rows.lowerBound, rect.columns.lowerBound] else { return false }
        var lines = top.text.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }[...]
        let slots = rect.rows.flatMap { r in rect.columns.map { (r, $0) } }
        for (i, (r, c)) in slots.enumerated() {
            let text = i == slots.count - 1 ? lines.joined(separator: "\n") : lines.popFirst() ?? ""
            if i == 0 {
                top.text = text
                top.rowspan = 1
                top.colspan = 1
                self[r, c] = top
            } else {
                self[r, c] = Cell(text: text)
            }
        }
        return true
    }

    // MARK: Checks

    /// Every slot covered exactly once, by a cell inside the table: what each edit must leave.
    public var isConsistent: Bool {
        guard rows.allSatisfy({ $0.cells.count == width }) else { return false }
        var covered = Array(repeating: Array(repeating: 0, count: width), count: height)
        for r in 0..<height {
            for c in 0..<width {
                guard let cell = self[r, c] else { continue }
                guard cell.rowspan >= 1, cell.colspan >= 1, r + cell.rowspan <= height, c + cell.colspan <= width else { return false }
                for rr in r..<(r + cell.rowspan) {
                    for cc in c..<(c + cell.colspan) { covered[rr][cc] += 1 }
                }
            }
        }
        return covered.allSatisfy { $0.allSatisfy { $0 == 1 } }
    }
}
