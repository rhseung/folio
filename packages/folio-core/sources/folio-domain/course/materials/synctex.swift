import Foundation

/// The SyncTeX data of one TeX build, read for the way back from a point in the PDF to the source line that put text
/// there (#41).
///
/// Written here rather than taken from a package: the only parser is the C one in TeX Live (`synctex_parser.c`), with
/// no Swift package around it, and going from a page point to a line needs only the boxes and their positions.
public struct SyncTeX: Sendable, Equatable {
    public struct Place: Sendable, Equatable {
        /// As the engine opened it: an absolute path when the build ran with real file names.
        public var file: String
        public var line: Int

        public init(file: String, line: Int) {
            self.file = file
            self.line = line
        }
    }

    /// A position a record of the source put on the page, in PDF points from the page's top-left corner.
    struct Mark: Sendable, Equatable {
        var tag: Int
        var line: Int
        var x: Double
    }

    /// One line of type (`(` record): its rectangle around the baseline, and what was set on it in reading order.
    struct Row: Sendable, Equatable {
        var tag: Int
        var line: Int
        var x: Double
        var baseline: Double
        var width: Double
        var height: Double
        var depth: Double
        var marks: [Mark] = []

        var top: Double { baseline - height }
        var bottom: Double { baseline + depth }
        var area: Double { width * (height + depth) }

        func contains(x px: Double, y py: Double) -> Bool {
            px >= x && px <= x + width && py >= top && py <= bottom
        }

        func distance(x px: Double, y py: Double) -> Double {
            let dx = max(x - px, 0, px - (x + width))
            let dy = max(top - py, 0, py - bottom)
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    var inputs: [Int: String] = [:]
    /// Rows by 1-based page number.
    var pages: [Int: [Row]] = [:]

    /// TeX's scaled points per PDF point: 65536 per TeX point, 72.27 TeX points per inch, 72 PDF points per inch.
    static let scaledPerPoint = 65536 * 72.27 / 72

    /// Reads the uncompressed text of a `.synctex` file.
    public init(text: String) {
        var unit = 1.0
        var magnification = 1000.0
        var xOffset = 0.0
        var yOffset = 0.0
        var page = 0
        var rows: [Row] = []
        // Indices into `rows` of the `(` records still open; `[` boxes hold rows but no marks of their own, so they
        // stand on the stack as nil.
        var open: [Int?] = []
        var inContent = false

        func scale(_ value: Int, offset: Double) -> Double {
            (Double(value) * unit * magnification / 1000 + offset) / Self.scaledPerPoint
        }

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = Substring(raw)
            if !inContent {
                if let value = Self.field("Unit:", line) { unit = Double(value) ?? unit }
                if let value = Self.field("Magnification:", line) { magnification = Double(value) ?? magnification }
                if let value = Self.field("X Offset:", line) { xOffset = Double(value) ?? xOffset }
                if let value = Self.field("Y Offset:", line) { yOffset = Double(value) ?? yOffset }
                if line == "Content:" { inContent = true }
            }
            if let input = Self.field("Input:", line) {
                let parts = input.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2, let tag = Int(parts[0]) { inputs[tag] = String(parts[1]) }
                continue
            }
            guard inContent, let kind = line.first else { continue }
            switch kind {
            case "{":
                page = Int(line.dropFirst()) ?? page
                rows = []
                open = []
            case "}":
                pages[page] = rows
            case "[":
                open.append(nil)
            case "]", ")":
                _ = open.popLast()
            case "(":
                guard let record = Self.record(line.dropFirst()), record.size.count == 3 else {
                    open.append(nil)
                    continue
                }
                let row = Row(tag: record.tag, line: record.line, x: scale(record.h, offset: xOffset), baseline: scale(record.v, offset: yOffset),
                              width: scale(record.size[0], offset: 0), height: scale(record.size[1], offset: 0), depth: scale(record.size[2], offset: 0))
                // A row inside another row (an `\hbox`, a formula) is also a place on the outer one.
                if let parent = open.last ?? nil { rows[parent].marks.append(Mark(tag: row.tag, line: row.line, x: row.x)) }
                rows.append(row)
                open.append(rows.count - 1)
            case "h", "v", "k", "g", "$", "x":
                guard let record = Self.record(line.dropFirst()), let parent = open.last ?? nil else { continue }
                rows[parent].marks.append(Mark(tag: record.tag, line: record.line, x: scale(record.h, offset: xOffset)))
            default:
                continue
            }
        }
    }

    /// The source line under a point of a page (1-based), in PDF points from the page's top-left corner. The smallest
    /// row around the point is the line of type clicked, or the nearest one when the click fell between lines; on it,
    /// the last thing set before the point names the line, since a paragraph's row carries the line where TeX ended
    /// the paragraph, not where its words are.
    public func place(page: Int, x: Double, y: Double) -> Place? {
        guard let rows = pages[page]?.filter({ $0.area > 0 }), !rows.isEmpty else { return nil }
        let around = rows.filter { $0.contains(x: x, y: y) }
        let row = around.min { $0.area < $1.area }
            ?? rows.min { $0.distance(x: x, y: y) < $1.distance(x: x, y: y) }
        guard let row else { return nil }

        let mark = row.marks.last { $0.x <= x } ?? row.marks.first
        let tag = mark?.tag ?? row.tag
        let line = mark?.line ?? row.line
        guard let file = inputs[tag], !file.isEmpty, line > 0 else { return nil }
        return Place(file: file, line: line)
    }

    private static func field(_ name: String, _ line: Substring) -> Substring? {
        line.hasPrefix(name) ? line.dropFirst(name.count) : nil
    }

    /// `tag,line[,column]:h,v[:W,H,D]`, after the record's type character.
    private static func record(_ body: Substring) -> (tag: Int, line: Int, h: Int, v: Int, size: [Int])? {
        let fields = body.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count >= 2 else { return nil }
        let source = fields[0].split(separator: ",").compactMap { Int($0) }
        let point = fields[1].split(separator: ",").compactMap { Int($0) }
        guard source.count >= 2, point.count == 2 else { return nil }
        let size = fields.count > 2 ? fields[2].split(separator: ",").compactMap { Int($0) } : []
        return (source[0], source[1], point[0], point[1], size)
    }
}
