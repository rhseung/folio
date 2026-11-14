import Foundation

public enum NoteImages {
    // FolioDomain `MaterialFormat`의 이미지 확장자를 되풀이한다. `AppLinkWikiTests`가 양쪽이 같은지 확인한다.
    public static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp"]
    static var link: Regex<(Substring, Substring)> { /!\[[^\]]*\]\(<?([^)>]+?)>?(?:\s+"[^"]*")?\)/ }
    static var wiki: Regex<(Substring, Substring)> { /!\[\[([^\]|#]+?)\\?(?:[|#][^\]]*)?\]\]/ }

    public enum Reference: Equatable, Sendable {
        case path(String)
        case name(String)
    }

    public static func references(in body: String) -> [Reference] {
        var found: [(String.Index, Reference)] = []
        for m in body.matches(of: link) {
            let raw = String(m.1).trimmingCharacters(in: .whitespaces)
            guard !raw.contains("://") else { continue }
            found.append((m.range.lowerBound, .path(raw.removingPercentEncoding ?? raw)))
        }
        for m in body.matches(of: wiki) { found.append((m.range.lowerBound, .name(String(m.1).trimmingCharacters(in: .whitespaces)))) }
        var seen = Set<String>()
        return found.sorted { $0.0 < $1.0 }.map(\.1).filter { ref in
            let file =
                switch ref {
                case .path(let p): p
                case .name(let n): n
                }
            return extensions.contains((file as NSString).pathExtension.lowercased()) && seen.insert(file).inserted
        }
    }
}
