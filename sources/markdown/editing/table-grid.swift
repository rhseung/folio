import Foundation

/// A GFM table as rows of cell texts, the header first, every row as wide as the table.
public struct TableGrid: Equatable, Sendable {
    /// `left`, `center` or `right` for each column; nil where the delimiter row gives none.
    public var alignments: [String?]
    /// Each cell's markdown as written between the pipes, unescaped pipes and all.
    public var rows: [[String]]

    public init(alignments: [String?], rows: [[String]]) {
        self.alignments = alignments
        self.rows = rows
    }

    public var width: Int { alignments.count }
    public var height: Int { rows.count }

    public subscript(row: Int, column: Int) -> String {
        get { rows[row][column] }
        set { rows[row][column] = newValue }
    }

    public mutating func insertRow(at index: Int) {
        rows.insert(Array(repeating: "", count: width), at: index)
    }

    public mutating func removeRow(at index: Int) {
        rows.remove(at: index)
    }

    public mutating func moveRow(_ index: Int, by step: Int) -> Bool {
        let other = index + step
        guard step == 1 || step == -1, rows.indices.contains(index), rows.indices.contains(other) else { return false }
        rows.swapAt(index, other)
        return true
    }

    public mutating func insertColumn(at index: Int) {
        for r in rows.indices { rows[r].insert("", at: index) }
        alignments.insert(nil, at: index)
    }

    public mutating func removeColumn(at index: Int) {
        for r in rows.indices { rows[r].remove(at: index) }
        alignments.remove(at: index)
    }

    public mutating func moveColumn(_ index: Int, by step: Int) -> Bool {
        let other = index + step
        guard step == 1 || step == -1, alignments.indices.contains(index), alignments.indices.contains(other) else { return false }
        for r in rows.indices { rows[r].swapAt(index, other) }
        alignments.swapAt(index, other)
        return true
    }
}
