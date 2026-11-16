import Foundation

// 패키지를 쓰지 않고 직접 구현한다. 파서는 TeX Live의 C 구현(`synctex_parser.c`)뿐이고 그것을 감싼 Swift 패키지가
// 없다. 또 쪽의 점에서 원문 줄을 찾는 데에는 상자와 그 위치만 있으면 된다.
public struct SyncTeX: Sendable, Equatable {
    public struct Place: Sendable, Equatable {
        public var file: String
        public var line: Int

        public init(file: String, line: Int) {
            self.file = file
            self.line = line
        }
    }

    struct Mark: Sendable, Equatable {
        var tag: Int
        var line: Int
        var x: Double
    }

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
    var pages: [Int: [Row]] = [:]

    // TeX 포인트 하나는 65536 scaled point이고, 1인치는 72.27 TeX 포인트이자 72 PDF 포인트다.
    static let scaledPerPoint = 65536 * 72.27 / 72

    public init(text: String) {
        var unit = 1.0
        var magnification = 1000.0
        var xOffset = 0.0
        var yOffset = 0.0
        var page = 0
        var rows: [Row] = []
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
                let row = Row(
                    tag: record.tag, line: record.line, x: scale(record.h, offset: xOffset), baseline: scale(record.v, offset: yOffset),
                    width: scale(record.size[0], offset: 0), height: scale(record.size[1], offset: 0),
                    depth: scale(record.size[2], offset: 0))
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

    // 문단의 줄은 단어가 있는 줄이 아니라 TeX가 문단을 끝낸 원문 줄을 지닌다. 그래서 그 줄 위에서 점 앞에 마지막으로
    // 놓인 것이 원문 줄을 정한다.
    public func place(page: Int, x: Double, y: Double) -> Place? {
        guard let rows = pages[page]?.filter({ $0.area > 0 }), !rows.isEmpty else { return nil }
        let around = rows.filter { $0.contains(x: x, y: y) }
        let row =
            around.min { $0.area < $1.area }
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

    // 레코드 종류 문자 뒤의 꼴은 `tag,line[,column]:h,v[:W,H,D]`이다.
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
