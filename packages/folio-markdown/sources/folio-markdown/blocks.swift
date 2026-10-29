import Foundation

/// ```` ```cb-table ```` holding JSON (docs/SPEC.md "표 블록"): used only when a table needs merged cells or
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
    /// First column rendered as headers.
    public var headerColumn: Bool?

    static let alignments: Set<String> = ["left", "center", "right"]

    static func render(json: String) -> String {
        guard let table = try? JSONDecoder().decode(CBTable.self, from: Data(json.utf8)) else {
            return "<pre class=\"invalid-block\">\(HTMLRenderer.escape(json))</pre>\n"
        }
        let columns = table.columns ?? []
        let cols = columns.map { c in "<col\(c.width.map { " style=\"width:\(Int($0))px\"" } ?? "")>" }.joined()
        let rows = table.rows.map { row in
            var column = 0
            let cells = row.cells.enumerated().map { i, cell in
                let isHeader = row.header == true || (table.headerColumn == true && i == 0)
                let tag = isHeader ? "th" : "td"
                let align = column < columns.count ? columns[column].align.flatMap { alignments.contains($0) ? " style=\"text-align:\($0)\"" : nil } ?? "" : ""
                let span = (cell.colspan.map { $0 > 1 ? " colspan=\"\($0)\"" : "" } ?? "") + (cell.rowspan.map { $0 > 1 ? " rowspan=\"\($0)\"" : "" } ?? "")
                column += cell.colspan ?? 1
                return "<\(tag)\(span)\(align)>\(HTMLRenderer.render(markdown: cell.text))</\(tag)>"
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
