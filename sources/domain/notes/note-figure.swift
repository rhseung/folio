import CryptoKit
import Foundation

public enum NoteFigure {
    public static let folder = CourseFolder.notes.rawValue + "/" + StandardLayout.noteAssetsFolder
    static let other: Set<String> = MaterialFormat.imageExtensions.union(["pdf", "html"])

    public static func fileName(_ given: String) -> String? {
        var name = given.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in [folder + "/", StandardLayout.noteAssetsFolder + "/"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
            break
        }
        let ext = (name as NSString).pathExtension.lowercased()
        if other.contains(ext) { return nil }
        if ext != "svg" { name += ".svg" }
        guard name.count > 4, !name.hasPrefix("."), !name.contains(where: { "/\\:".contains($0) || $0.isNewline }) else { return nil }
        return name
    }

    public static func path(_ fileName: String) -> String { folder + "/" + fileName }

    public enum Problem: Hashable, Sendable {
        case notXML(line: Int, reason: String)
        case notSVG(root: String)
        case script(String)
        case external(String)
        case color(String)
        case longText(String)
        case bigArrow(String)
        case tex(String, reason: String)
        case tspanMath(String)
        case overlap(String, String)
        case onLine(String, String)
        case onEdge(String, String)
        case outside(String)
        case notThrough(String, String, gap: String)
        case noPoint(String, String)
        case notDrawn(String)

        public var message: String {
            switch self {
            case .notXML(let line, let reason): String(localized: .figureProblemNotXml(line, reason))
            case .notSVG(let root): String(localized: .figureProblemNotSvg(root))
            case .script(let what): String(localized: .figureProblemScript(what))
            case .external(let ref): String(localized: .figureProblemExternal(ref))
            case .color(let value): String(localized: .figureProblemColor(value))
            case .longText(let text): String(localized: .figureProblemLongText(text, FigureStyle.labelLimit))
            case .bigArrow(let marker): String(localized: .figureProblemBigArrow(marker))
            case .tex(let tex, let reason): String(localized: .figureProblemTex(tex, reason))
            case .tspanMath(let text): String(localized: .figureProblemTspanMath(text))
            case .overlap(let a, let b): String(localized: .figureProblemOverlap(a, b))
            case .onLine(let label, let shape): String(localized: .figureProblemOnLine(label, shape))
            case .onEdge(let label, let shape): String(localized: .figureProblemOnEdge(label, shape))
            case .outside(let label): String(localized: .figureProblemOutside(label))
            case .notThrough(let shape, let point, let gap): String(localized: .figureProblemNotThrough(shape, point, gap))
            case .noPoint(let shape, let point): String(localized: .figureProblemNoPoint(shape, point))
            case .notDrawn(let reason): String(localized: .figureProblemNotDrawn(reason))
            }
        }
    }

    // 노트는 SVG를 이미지로 보인다. 이미지는 스크립트를 실행하지 않고 다른 것을 불러오지 않으므로, 그런 부분은
    // 아무 표시 없이 빠진다. 또 이미지는 페이지 색을 읽지 못하므로 색은 그림 스타일 표의 클래스로만 칠한다. 클래스의
    // 라이트·다크 값은 쓸 때 넣는다(NoteFigureFinish). 쓸 때 넣은 `<style>`과 `<defs>`는 검사하지 않는다.
    public static func problems(_ svg: String) -> [Problem] {
        let reader = SVGReader()
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = reader
        // 엔티티는 다른 파일을 끌어올 수 있다.
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            let reason = parser.parserError.map { ($0 as NSError).localizedDescription } ?? ""
            return [.notXML(line: parser.lineNumber, reason: reason)]
        }

        var found: [Problem] = []
        func add(_ p: Problem) { if !found.contains(p) { found.append(p) } }
        if let root = reader.root, local(root) != "svg" { add(.notSVG(root: root)) }
        for (element, attributes) in reader.elements {
            if local(element).lowercased() == "script" { add(.script("<\(element)>")) }
            for (name, value) in attributes {
                let key = name.lowercased()
                if key.hasPrefix("on") { add(.script(name)) }
                if key == "href" || key == "src" || key.hasSuffix(":href"), !inside(value) { add(.external(value)) }
                if key == "style" {
                    cssProblems(value).forEach(add)
                    colorProblems(declarations: value).forEach(add)
                }
                if colorAttributes.contains(key), !plain(value) { add(.color(value.trimmingCharacters(in: .whitespaces))) }
            }
            if local(element) == "marker", tooBig(attributes) { add(.bigArrow(attributes["id"].map { "#" + $0 } ?? "<marker>")) }
        }
        cssProblems(reader.styles).forEach(add)
        colorProblems(declarations: reader.styles).forEach(add)
        for label in reader.labels where visibleLength(label) > FigureStyle.labelLimit { add(.longText(label)) }
        return found
    }

    static func cssProblems(_ css: String) -> [Problem] {
        var found = css.matches(of: /url\(\s*['"]?([^'")\s]*)/.ignoresCase()).map { String($0.1) }.filter { !inside($0) }.map(
            Problem.external)
        found += css.matches(of: /@import\s+([^;]+)/.ignoresCase()).map { .external(String($0.1).trimmingCharacters(in: .whitespaces)) }
        return found
    }

    static let colorAttributes: Set<String> = ["fill", "stroke", "color", "stop-color", "flood-color", "lighting-color"]

    static func colorProblems(declarations css: String) -> [Problem] {
        let declaration = /(?:^|[\s;{])(fill|stroke|color|stop-color|flood-color|lighting-color|background(?:-color)?)\s*:\s*([^;}]+)/
        let values = css.matches(of: declaration.ignoresCase()).map { String($0.2).trimmingCharacters(in: .whitespaces) }
        return values.filter { !plain($0) }.map(Problem.color)
    }

    // 색이 아니거나 색을 바깥에 맡기는 값이다. url()은 그라디언트와 무늬이고 바깥 주소는 따로 검사한다. var()는 이미지가
    // 페이지 변수를 읽지 못해 빈 값이 되므로 받지 않는다.
    static func plain(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces).replacing(/\s*!important$/.ignoresCase(), with: "").lowercased()
        return ["none", "transparent", "currentcolor", "inherit", "context-fill", "context-stroke", ""].contains(v) || v.hasPrefix("url(")
    }

    // 화살촉은 선 굵기의 배수로 그린다(markerUnits 기본값 strokeWidth, markerWidth와 markerHeight 기본값 3).
    // userSpaceOnUse면 표의 보통 선 굵기로 견준다.
    static func tooBig(_ attributes: [String: String]) -> Bool {
        let width = attributes["markerWidth"].flatMap(Double.init) ?? 3
        let height = attributes["markerHeight"].flatMap(Double.init) ?? 3
        let slack = FigureStyle.arrowSlack * (attributes["markerUnits"] == "userSpaceOnUse" ? FigureStyle.lineWidth : 1)
        return width > FigureStyle.arrow.length * slack || height > FigureStyle.arrow.width * slack
    }

    // 라벨의 글자 수다. `$…$` 수식 하나는 한 글자로 센다.
    static func visibleLength(_ text: String) -> Int {
        let collapsed = text.replacing("\\$", with: "x").replacing(/\$[^$]+\$/, with: "x")
        return collapsed.split(whereSeparator: \.isWhitespace).joined(separator: " ").count
    }

    static func inside(_ ref: String) -> Bool {
        let r = ref.trimmingCharacters(in: .whitespaces)
        return r.isEmpty || r.hasPrefix("#") || r.lowercased().hasPrefix("data:")
    }

    static func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }
}

private final class SVGReader: NSObject, XMLParserDelegate {
    var root: String?
    var elements: [(String, [String: String])] = []
    var styles = ""
    var labels: [String] = []
    private var inStyle = 0
    private var inText = 0
    private var label = ""
    // 쓸 때 넣은 `<style>`과 `<defs>` 안이다.
    private var own = 0

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]
    ) {
        if root == nil { root = name }
        if own > 0 || attributes["id"].map({ [FigureStyle.styleID, FigureStyle.defsID].contains($0) }) == true {
            own += 1
            return
        }
        elements.append((name, attributes))
        if NoteFigure.local(name) == "style" { inStyle += 1 }
        if NoteFigure.local(name) == "text" {
            if inText == 0 { label = "" }
            inText += 1
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if own > 0 {
            own -= 1
            return
        }
        if NoteFigure.local(name) == "style" { inStyle -= 1 }
        if NoteFigure.local(name) == "text" {
            inText -= 1
            if inText == 0 { labels.append(label.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard own == 0 else { return }
        if inStyle > 0 { styles += string }
        if inText > 0 { label += string }
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        guard own == 0 else { return }
        if inStyle > 0 { styles += String(decoding: block, as: UTF8.self) }
        if inText > 0 { label += String(bytes: block, encoding: .utf8) ?? "" }
    }
}
