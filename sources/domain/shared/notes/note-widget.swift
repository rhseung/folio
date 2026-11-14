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
