import CryptoKit
import Foundation

/// A picture a note embeds, kept in `Notes/assets` by file name. Not a material: a note's drawing would otherwise land
/// in the material list and its kinds. Only SVG, the one format Claude writes and the checks below can read.
public enum NoteFigure {
    public static let folder = CourseFolder.notes.rawValue + "/" + StandardLayout.noteAssetsFolder
    static let other: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "pdf", "html"]

    /// `graph`, `graph.svg`, `assets/graph.svg` or `Notes/assets/graph.svg` as `graph.svg`; nil for anything that
    /// isn't one SVG file right in `assets`.
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

    /// Course-relative.
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

    /// What keeps the SVG from drawing as written in a note. A note shows it as an image, which runs no script and
    /// loads nothing else, so such parts would quietly be missing; and an image can't read the page's colors, so
    /// without a dark rule of its own its dark strokes and words vanish on the dark page.
    public static func problems(_ svg: String) -> [Problem] {
        let reader = SVGReader()
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = reader
        // Entities could pull in other files.
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

    /// A reference the picture can follow on its own: a part of itself or data written in.
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

/// A page a note runs in a `cb-widget` block, kept in the course's `.folio/widgets/<id>.html`.
public enum NoteWidget {
    public typealias ID = UUID

    /// Course-relative.
    public static func path(_ id: ID) -> String {
        StandardLayout.metadataFolder + "/" + StandardLayout.widgetsFolder + "/" + id.uuidString + ".html"
    }

    /// What a widget's page may do: run its own inline code and styles, and load nothing. The app's frame and
    /// `folio note widget render` run widgets under the same one.
    public static let policy = [
        "default-src 'none'", "script-src 'unsafe-inline' 'unsafe-eval'", "style-src 'unsafe-inline'",
        "img-src data: blob:", "font-src data:", "media-src data: blob:", "form-action 'none'", "base-uri 'none'",
    ].joined(separator: "; ")

    /// The policy as the page's first element: WebKit doesn't apply a policy header to a frame's page, only to a
    /// window's. After a doctype, which a tag ahead of it would turn off; on the doctype's line, so the page's own line
    /// numbers in errors stay as written.
    public static func withPolicy(_ page: Data) -> Data {
        let meta = Data("<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">".utf8)
        let head = String(decoding: page.prefix(256), as: UTF8.self)
        guard let doctype = head.firstMatch(of: /^\s*<!doctype[^>]*>/.ignoresCase()) else { return meta + page }
        let end = head[..<doctype.range.upperBound].utf8.count
        return page.prefix(end) + meta + page.dropFirst(end)
    }

    /// The policy doesn't cover peer connections, which could otherwise carry data out.
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

    /// What can't work in the widget's frame, whose policy loads nothing from outside: the page would run without
    /// it and show nothing where it was. Links are left alone; the frame doesn't open them either way.
    public static func problems(_ html: String) -> [Problem] {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [.empty] }
        var found: [String] = []
        // Quoted anywhere, so a script's `img.src = "plot.png"` counts too; unquoted only inside a tag, where a
        // script's `img.src = url` (a variable) can't be.
        found += html.matches(of: /[\s.]src\s*=\s*(?:"([^"]*)"|'([^']*)')/.ignoresCase()).map { String($0.1 ?? $0.2 ?? "") }
        found += html.matches(of: /<[a-z][^>]*\ssrc\s*=\s*([^'"\s>]+)/.ignoresCase()).map { String($0.1) }
        found += html.matches(of: /<link\b[^>]*\bhref\s*=\s*['"]?([^'"\s>]+)/.ignoresCase()).map { String($0.1) }
        found += html.matches(of: /url\(\s*['"]?([^'")\s]*)/.ignoresCase()).map { String($0.1) }
        found += html.matches(of: /@import\s+(?:url\()?\s*['"]?([^'";)\s]+)/.ignoresCase()).map { String($0.1) }
        let problems = found.filter { !inside($0) }.map(Problem.external)
        var seen: Set<Problem> = []
        return problems.filter { seen.insert($0).inserted }
    }

    /// What the policy lets a page use: a part of itself, data written in, or something its script made. A value
    /// built in a template string (`${…}`) is only known when the script runs.
    static func inside(_ ref: String) -> Bool {
        let r = ref.trimmingCharacters(in: .whitespaces).lowercased()
        return r.isEmpty || r.hasPrefix("#") || r.hasPrefix("data:") || r.hasPrefix("blob:") || r.contains("${")
    }
}

public enum ContentHash {
    /// What `show` reports and `--expect` checks: the text as it was read.
    public static func of(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
