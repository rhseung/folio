import FolioMarkdown
import Markdown
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor enum ReaderPictures {
    /// A picture drawn top-down. On the Mac it's drawn when shown, so its dynamic colors follow the appearance.
    static func draw(_ size: CGSize, _ body: @escaping (CGContext) -> Void) -> PlatformImage {
        #if os(macOS)
        return NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            body(context)
            return true
        }
        #else
        return UIGraphicsImageRenderer(size: size).image { body($0.cgContext) }
        #endif
    }

    /// Where an interactive widget would be; the read view doesn't run note scripts.
    static func placeholder(_ size: CGSize) -> (image: PlatformImage, size: CGSize) {
        let image = draw(size) { context in
            let path = CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerWidth: 8, cornerHeight: 8, transform: nil)
            context.addPath(path)
            context.setFillColor(NoteLook.fill.cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(NoteLook.line.cgColor)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.strokePath()
            let label = NSAttributedString(string: "widget", attributes: [.font: NoteLook.font(NoteLook.labelSize), .foregroundColor: NoteLook.text3])
            let s = label.size()
            withText(context) { label.draw(at: CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2)) }
        }
        return (image, size)
    }

    static func withText(_ context: CGContext, _ body: () -> Void) {
        #if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsPushContext(context)
        body()
        UIGraphicsPopContext()
        #endif
    }
}

/// Markdown tables and `cb-table` blocks, drawn as one picture: TextKit has no tables on iPadOS, and a picture keeps
/// both platforms the same.
@MainActor enum ReaderTable {
    struct Cell {
        var row: Int, column: Int
        var rows = 1, columns = 1
        var text: NSAttributedString
        var header: Bool
    }

    static let padding = CGSize(width: 12, height: 8)

    static func render(_ table: Markdown.Table, builder: ReaderBuilder) -> (image: PlatformImage, size: CGSize)? {
        var b = builder
        let alignments = table.columnAlignments
        var cells: [Cell] = []
        let rows = [Array(table.head.cells)] + table.body.rows.map { Array($0.cells) }
        for (r, row) in rows.enumerated() {
            for (c, cell) in row.enumerated() {
                let text = b.cell(Array(cell.inlineChildren), weight: r == 0 ? .semibold : .regular)
                cells.append(Cell(row: r, column: c, text: aligned(text, c < alignments.count ? alignments[c] : nil), header: r == 0))
            }
        }
        return draw(cells, widths: [], width: builder.width)
    }

    static func render(json: String, builder: ReaderBuilder) -> (image: PlatformImage, size: CGSize)? {
        guard let table = try? JSONDecoder().decode(CBTable.self, from: Data(json.utf8)) else { return nil }
        var b = builder
        let columns = table.columns ?? []
        var taken = Set<[Int]>()
        var cells: [Cell] = []
        for (r, row) in table.rows.enumerated() {
            var c = 0
            for (i, cell) in row.cells.enumerated() {
                while taken.contains([r, c]) { c += 1 }
                let header = row.header == true || (table.headerColumn == true && i == 0)
                let span = (rows: max(1, cell.rowspan ?? 1), columns: max(1, cell.colspan ?? 1))
                for dr in 0..<span.rows { for dc in 0..<span.columns { taken.insert([r + dr, c + dc]) } }
                let align: Markdown.Table.ColumnAlignment? = switch c < columns.count ? columns[c].align : nil {
                case "center": .center
                case "right": .right
                case "left": .left
                default: nil
                }
                let text = b.cell(markdown: cell.text, weight: header ? .semibold : .regular)
                cells.append(Cell(row: r, column: c, rows: span.rows, columns: span.columns, text: aligned(text, align), header: header))
                c += span.columns
            }
        }
        return draw(cells, widths: columns.map { $0.width.map { CGFloat($0) } }, width: builder.width)
    }

    private static func aligned(_ text: NSAttributedString, _ alignment: Markdown.Table.ColumnAlignment?) -> NSAttributedString {
        guard let alignment else { return text }
        let s = NSMutableAttributedString(attributedString: text)
        s.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: s.length)) { value, r, _ in
            let p = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            p.alignment = switch alignment { case .center: .center; case .right: .right; case .left: .left }
            s.addAttribute(.paragraphStyle, value: p, range: r)
        }
        return s
    }

    private static func height(_ text: NSAttributedString, _ width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    /// Columns take their natural width, shrunk together when the table is wider than the page.
    private static func draw(_ cells: [Cell], widths fixed: [CGFloat?], width page: CGFloat) -> (image: PlatformImage, size: CGSize)? {
        guard !cells.isEmpty else { return nil }
        let columnCount = cells.map { $0.column + $0.columns }.max()!
        let rowCount = cells.map { $0.row + $0.rows }.max()!
        var widths = (0..<columnCount).map { c in c < fixed.count ? fixed[c] ?? 0 : 0 }
        for cell in cells where cell.columns == 1 && (cell.column >= fixed.count || fixed[cell.column] == nil) {
            let natural = ceil(cell.text.boundingRect(with: CGSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin], context: nil).width)
            widths[cell.column] = max(widths[cell.column], min(natural, 360) + padding.width * 2)
        }
        widths = widths.map { max($0, 48) }
        let total = widths.reduce(0, +)
        if total > page { widths = widths.map { max(48, floor($0 * page / total)) } }
        var heights = Array(repeating: CGFloat(0), count: rowCount)
        func span(_ list: [CGFloat], _ from: Int, _ count: Int) -> CGFloat { list[from..<(from + count)].reduce(0, +) }
        for cell in cells.sorted(by: { $0.rows < $1.rows }) {
            let need = height(cell.text, span(widths, cell.column, cell.columns) - padding.width * 2) + padding.height * 2
            let have = span(heights, cell.row, cell.rows)
            if need > have { heights[cell.row + cell.rows - 1] += need - have }
        }
        let size = CGSize(width: widths.reduce(0, +), height: heights.reduce(0, +))
        let image = ReaderPictures.draw(size) { context in
            let outer = CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerWidth: 8, cornerHeight: 8, transform: nil)
            context.saveGState()
            context.addPath(outer)
            context.clip()
            for cell in cells {
                let rect = CGRect(x: span(widths, 0, cell.column), y: span(heights, 0, cell.row),
                                  width: span(widths, cell.column, cell.columns), height: span(heights, cell.row, cell.rows))
                if cell.header {
                    context.setFillColor(NoteLook.fill.cgColor)
                    context.fill(rect)
                }
                context.setStrokeColor(NoteLook.line.cgColor)
                context.setLineWidth(1)
                context.stroke(rect)
                ReaderPictures.withText(context) {
                    cell.text.draw(with: rect.insetBy(dx: padding.width, dy: padding.height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                }
            }
            context.restoreGState()
            context.addPath(outer)
            context.setStrokeColor(NoteLook.line.cgColor)
            context.strokePath()
        }
        return (image, size)
    }
}
