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

public enum NoteWidget {
    public typealias ID = UUID

    public static func path(_ id: ID) -> String {
        StandardLayout.metadataFolder + "/" + StandardLayout.widgetsFolder + "/" + id.uuidString + ".html"
    }

    public static let policy = [
        "default-src 'none'", "script-src 'unsafe-inline' 'unsafe-eval'", "style-src 'unsafe-inline'",
        "img-src data: blob:", "font-src data:", "media-src data: blob:", "form-action 'none'", "base-uri 'none'",
    ].joined(separator: "; ")

    // WebKit은 창의 페이지에만 정책 헤더를 적용하고 프레임의 페이지에는 적용하지 않으므로, 정책을 페이지의 첫
    // 요소로 넣는다. 앞에 태그가 있으면 doctype이 꺼지므로 doctype 뒤에 넣고, 오류의 줄 번호가 쓴 그대로 남도록
    // doctype과 같은 줄에 넣는다.
    public static func withPolicy(_ page: Data) -> Data {
        let meta = Data("<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">".utf8)
        let head = String(decoding: page.prefix(256), as: UTF8.self)
        guard let doctype = head.firstMatch(of: /^\s*<!doctype[^>]*>/.ignoresCase()) else { return meta + page }
        let end = head[..<doctype.range.upperBound].utf8.count
        return page.prefix(end) + meta + page.dropFirst(end)
    }

    // 정책은 peer connection을 막지 않으므로, 막지 않으면 peer connection이 데이터를 밖으로 내보낼 수 있다.
    public static let noPeersScript =
        "for (const k of ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel']) { try { delete window[k]; window[k] = undefined } catch {} }"

    public enum Problem: Hashable, Sendable {
        case empty
        case external(String)

        public var message: String {
            switch self {
            case .empty: String(localized: .widgetProblemEmpty)
            case .external(let ref): String(localized: .widgetProblemExternal(ref))
            }
        }
    }

    public static func problems(_ html: String) -> [Problem] {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [.empty] }
        var found: [String] = []
        // 따옴표로 감싼 값은 어디서든 세므로 스크립트의 `img.src = "plot.png"`도 센다. 따옴표 없는 값은 태그 안에서만
        // 센다. 스크립트의 `img.src = url`(변수)은 태그 안에 있을 수 없기 때문이다.
        found += html.matches(of: /[\s.]src\s*=\s*(?:"([^"]*)"|'([^']*)')/.ignoresCase()).map { String($0.1 ?? $0.2 ?? "") }
        found += html.matches(of: /<[a-z][^>]*\ssrc\s*=\s*([^'"\s>]+)/.ignoresCase()).map { String($0.1) }
        found += html.matches(of: /<link\b[^>]*\bhref\s*=\s*['"]?([^'"\s>]+)/.ignoresCase()).map { String($0.1) }
        found += html.matches(of: /url\(\s*['"]?([^'")\s]*)/.ignoresCase()).map { String($0.1) }
        found += html.matches(of: /@import\s+(?:url\()?\s*['"]?([^'";)\s]+)/.ignoresCase()).map { String($0.1) }
        let problems = found.filter { !inside($0) }.map(Problem.external)
        var seen: Set<Problem> = []
        return problems.filter { seen.insert($0).inserted }
    }

    static func inside(_ ref: String) -> Bool {
        let r = ref.trimmingCharacters(in: .whitespaces).lowercased()
        return r.isEmpty || r.hasPrefix("#") || r.hasPrefix("data:") || r.hasPrefix("blob:") || r.contains("${")
    }
}

public enum ContentHash {
    public static func of(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
