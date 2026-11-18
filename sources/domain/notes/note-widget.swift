import CryptoKit
import Foundation

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
        case blackMarker(String)
        case fixedMarker(String, color: String)

        public var message: String {
            switch self {
            case .empty: String(localized: .widgetProblemEmpty)
            case .external(let ref): String(localized: .widgetProblemExternal(ref))
            case .blackMarker(let marker): String(localized: .widgetProblemMarkerBlack(marker))
            case .fixedMarker(let marker, let color): String(localized: .widgetProblemMarkerFixed(marker, color))
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

    // 위젯이 직접 그린 화살촉 중 테마를 따르지 않는 것이다. 쓰기를 막지 않고 그려 보기에서만 알린다. 스크립트 문자열
    // 안의 `<marker>`도 보려고 HTML을 읽지 않고 글로 찾으므로, 놓치는 경우는 있어도 막을 근거로 쓰지 않는다.
    // 촉의 색은 `<marker>`와 그 안 도형의 fill·stroke, `<style>`에서 `marker` 요소를 고르는 규칙에서 읽는다. fill이 하나도
    // 없으면 SVG 기본값인 검정이다. class를 단 촉은 위젯의 CSS가 칠한다고 보고 넘어간다.
    public static func markerProblems(_ html: String) -> [Problem] {
        let rules = html.matches(of: /<style\b[^>]*>(.*?)<\/style\s*>/.ignoresCase().dotMatchesNewlines()).flatMap { style in
            String(style.1).matches(of: /([^{}]*(?:^|[^\w-])marker(?![\w-])[^{}]*)\{([^}]*)\}/.ignoresCase()).map { String($0.2) }
        }
        let ruled = paints(declarations: rules.joined(separator: ";"))
        var found: [Problem] = []
        for m in html.matches(of: /<marker\b([^>]*)>(.*?)<\/marker\s*>/.ignoresCase().dotMatchesNewlines()) {
            let tags = String(m.0)
            let id = m.1.firstMatch(of: /\bid\s*=\s*\\?["']([^"'\\]+)/).map { "#" + $0.1 } ?? "<marker>"
            var fills = ruled.fills, strokes = ruled.strokes
            for a in tags.matches(of: /\b(fill|stroke)\s*=\s*\\?["']([^"'\\]*)/.ignoresCase()) {
                if a.1.lowercased() == "fill" { fills.append(String(a.2)) } else { strokes.append(String(a.2)) }
            }
            for a in tags.matches(of: /\bstyle\s*=\s*\\?["']([^"'\\]*)/.ignoresCase()) {
                let declared = paints(declarations: String(a.1))
                fills += declared.fills
                strokes += declared.strokes
            }
            let fixed = (fills + strokes).map { $0.trimmingCharacters(in: .whitespaces) }.first { !followsTheme($0) }
            if let fixed {
                found.append(.fixedMarker(id, color: fixed))
            } else if fills.isEmpty, tags.firstMatch(of: /\bclass(?:Name)?\s*=/) == nil {
                found.append(.blackMarker(id))
            }
        }
        var seen: Set<Problem> = []
        return found.filter { seen.insert($0).inserted }
    }

    static func paints(declarations css: String) -> (fills: [String], strokes: [String]) {
        var fills: [String] = [], strokes: [String] = []
        for d in css.matches(of: /(?:^|[\s;{])(fill|stroke)\s*:\s*([^;}"']+)/.ignoresCase()) {
            if d.1.lowercased() == "fill" { fills.append(String(d.2)) } else { strokes.append(String(d.2)) }
        }
        return (fills, strokes)
    }

    // CSS 변수와 currentColor는 노트 색을 따른다. `${…}`는 스크립트가 넣는 값이라 알 수 없다.
    static func followsTheme(_ paint: String) -> Bool {
        let v = paint.replacing(/\s*!important$/.ignoresCase(), with: "").lowercased()
        return v.hasPrefix("var(") || v.contains("${") || v.hasPrefix("url(")
            || ["none", "transparent", "currentcolor", "inherit", "context-fill", "context-stroke", ""].contains(v)
    }

    static func inside(_ ref: String) -> Bool {
        let r = ref.trimmingCharacters(in: .whitespaces).lowercased()
        return r.isEmpty || r.hasPrefix("#") || r.hasPrefix("data:") || r.hasPrefix("blob:") || r.contains("${")
    }

    // 애셋 서랍에 보일 이름이다. 스크립트가 나중에 바꾼 제목은 읽지 않는다. 서랍은 위젯을 돌리지 않고 파일만 읽기 때문이다.
    public static func title(_ html: String) -> String? {
        guard let m = html.firstMatch(of: /<title\b[^>]*>(.*?)<\/title\s*>/.ignoresCase().dotMatchesNewlines()) else { return nil }
        let entities = [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")]
        let text = entities.reduce(String(m.1)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : text
    }
}
