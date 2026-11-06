import Foundation

/// ```` ```cb-table ```` holding JSON: used only when a table needs merged cells or
/// block content in cells; simple tables stay plain markdown tables.
public struct CBTable: Codable, Equatable, Sendable {
    public static let language = "cb-table"

    public struct Column: Codable, Equatable, Sendable {
        public var width: Double?
        /// `left`, `center` or `right`.
        public var align: String?
    }

    public struct Cell: Codable, Equatable, Sendable {
        /// Markdown, may contain lists, math and line breaks.
        public var text: String
        public var colspan: Int?
        public var rowspan: Int?
    }

    public struct Row: Codable, Equatable, Sendable {
        public var header: Bool?
        public var cells: [Cell]
    }

    public var columns: [Column]?
    public var rows: [Row]
    public var headerColumn: Bool?

    static let alignments: Set<String> = ["left", "center", "right"]

    /// `draw` draws a cell's markdown, so its footnotes, embeds and references are drawn as the note's are. Laid out
    /// as the table editor lays it out (`TableSource.grid`), so a cell's column, which its alignment and the header
    /// column go by, counts the cells merged down into its row from above.
    static func render(json: String, draw: (String) -> String) -> String {
        guard let node = JSONNode.parse(json), let (grid, _) = TableSource.grid(node) else {
            return "<pre class=\"invalid-block\">\(HTMLRenderer.escape(json))</pre>\n"
        }
        let widths = grid.columns.map(\.width)
        let cols = widths.contains { $0 != nil } ? widths.map { w in "<col\(w.map { " style=\"width:\(JSONNode.number($0))px\"" } ?? "")>" }.joined() : ""
        let rows = grid.rows.enumerated().map { r, row in
            var first = true
            let cells = row.cells.enumerated().compactMap { c, slot -> String? in
                guard let cell = slot else { return nil }
                let tag = row.header || (grid.headerColumn == true && c == 0) ? "th" : "td"
                let align = grid.columns[c].align.flatMap { alignments.contains($0) ? " style=\"text-align:\($0)\"" : nil } ?? ""
                let span = (cell.colspan > 1 ? " colspan=\"\(cell.colspan)\"" : "") + (cell.rowspan > 1 ? " rowspan=\"\(cell.rowspan)\"" : "")
                // The stylesheet draws lines between sibling cells and none under the last row; a cell merged down
                // from above leaves the next one first in its row, and a merged cell can end on the last row.
                var classes: [String] = []
                if first, c > 0 { classes.append("after-merged") }
                if r + cell.rowspan == grid.height, r < grid.height - 1 { classes.append("to-end") }
                first = false
                let cls = classes.isEmpty ? "" : " class=\"\(classes.joined(separator: " "))\""
                return "<\(tag)\(cls)\(span)\(align)>\(draw(cell.text))</\(tag)>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }.joined()
        return "<table class=\"cb-table\">\(cols.isEmpty ? "" : "<colgroup>\(cols)</colgroup>")<tbody>\(rows)</tbody></table>\n"
    }
}

/// ```` ```cb-widget ```` holding `{"id": "<widget ID>", "height": 320}`; the HTML lives in `.folio/widgets/<id>.html`.
public struct CBWidget: Codable, Equatable, Sendable {
    public static let language = "cb-widget"

    public var id: UUID
    public var height: Double?

    static func render(json: String) -> String {
        guard let widget = try? JSONDecoder().decode(CBWidget.self, from: Data(json.utf8)) else {
            return "<pre class=\"invalid-block\">\(HTMLRenderer.escape(json))</pre>\n"
        }
        let height = widget.height.map { " style=\"height:\(Int($0))px\"" } ?? ""
        return "<div class=\"cb-widget\" data-widget=\"\(widget.id.uuidString)\"\(height)></div>\n"
    }
}
