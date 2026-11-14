import CryptoKit
import Foundation

public enum NoteFigure {
    public static let folder = CourseFolder.notes.rawValue + "/" + StandardLayout.noteAssetsFolder
    static let other: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "pdf", "html"]

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
        case noDarkRule

        public var message: String {
            switch self {
            case .notXML(let line, let reason): String(localized: .figureProblemNotXml(line, reason))
            case .notSVG(let root): String(localized: .figureProblemNotSvg(root))
            case .script(let what): String(localized: .figureProblemScript(what))
            case .external(let ref): String(localized: .figureProblemExternal(ref))
            case .noDarkRule: String(localized: .figureProblemNoDark)
            }
        }
    }

    // 노트는 SVG를 이미지로 보인다. 이미지는 스크립트를 실행하지 않고 다른 것을 불러오지 않으므로, 그런 부분은
    // 아무 표시 없이 빠진다. 또 이미지는 페이지 색을 읽지 못하므로, 자체 다크 규칙이 없으면 짙은 선과 글자가 다크
    // 페이지에서 보이지 않는다.
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
                if key == "style" { cssProblems(value).forEach(add) }
            }
        }
        cssProblems(reader.styles).forEach(add)
        if reader.styles.firstMatch(of: /prefers-color-scheme\s*:\s*dark/.ignoresCase()) == nil { add(.noDarkRule) }
        return found
    }

    static func cssProblems(_ css: String) -> [Problem] {
        var found = css.matches(of: /url\(\s*['"]?([^'")\s]*)/.ignoresCase()).map { String($0.1) }.filter { !inside($0) }.map(
            Problem.external)
        found += css.matches(of: /@import\s+([^;]+)/.ignoresCase()).map { .external(String($0.1).trimmingCharacters(in: .whitespaces)) }
        return found
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
    private var inStyle = 0

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]
    ) {
        if root == nil { root = name }
        elements.append((name, attributes))
        if NoteFigure.local(name) == "style" { inStyle += 1 }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if NoteFigure.local(name) == "style" { inStyle -= 1 }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inStyle > 0 { styles += string }
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        if inStyle > 0 { styles += String(decoding: block, as: UTF8.self) }
    }
}
