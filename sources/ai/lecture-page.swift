import FolioDomain
import Foundation

public struct LecturePage: Sendable, Equatable {
    public var title: String?
    public var body: String
    public var image: Data?

    public init(title: String?, body: String = "", image: Data? = nil) {
        self.title = title
        self.body = body
        self.image = image
    }

    public static let excerpt = 280
    public static let budget = 36_000
    public static let fewWords = 12
    static let repeatWords = 8
    public static let maxImages = 24
    public static let thumbnail: CGFloat = 512

    public static func excerptLength(pages: Int) -> Int {
        guard pages > 0 else { return excerpt }
        return max(min(excerpt, budget / pages), 60)
    }

    public static func excerpt(_ text: String, title: String?, limit: Int) -> String {
        var rest = text
        if let title, let range = rest.range(of: title) { rest.removeSubrange(range) }
        let words = rest.split(whereSeparator: { $0.isWhitespace || $0 == PageText.figure })
        var out = ""
        for word in words {
            if out.count + word.count + 1 > limit {
                if out.isEmpty { out = String(word.prefix(limit)) }
                return out + "…"
            }
            out += out.isEmpty ? String(word) : " " + word
        }
        return out
    }

    public static func pictured(texts: [String], titles: [String?]) -> [Int] {
        var seen: Set<String> = [], first: [Int] = [], then: [Int] = []
        for (i, text) in texts.enumerated() {
            let title = titles.indices.contains(i) ? titles[i] : nil
            let words = max(PageText.words(text) - (title.map(PageText.words) ?? 0), 0)
            let repeated = PageText.words(text) >= repeatWords && !seen.insert(shape(text)).inserted
            if words < fewWords || repeated {
                first.append(i)
            } else if PageText.figures(text) >= words {
                then.append(i)
            }
        }
        let firstKept = spread(first, maxImages)
        return (firstKept + spread(then, maxImages - firstKept.count)).sorted()
    }

    // 반복된 슬라이드는 꼬리말의 숫자("4-3", "4-67")만 다르므로 숫자를 뺀다.
    static func shape(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == PageText.figure || $0.isNumber }).joined(separator: " ")
    }

    static func spread(_ pages: [Int], _ count: Int) -> [Int] {
        guard count > 0 else { return [] }
        guard pages.count > count else { return pages }
        return (0..<count).map { pages[$0 * pages.count / count] }
    }
}
