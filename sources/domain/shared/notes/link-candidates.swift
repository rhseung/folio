import Foundation

public enum LinkCandidates {
    public static func order(_ hits: [SearchHit], course: UUID, excluding own: UUID? = nil) -> [SearchHit] {
        let kept = hits.filter { $0.item.id != own }
        return kept.filter { $0.item.courseId == course } + kept.filter { $0.item.courseId != course }
    }

    public static func pages(count: Int?, last: Int?, typed: String, limit: Int = 100) -> [Int] {
        let matches = { (n: Int) in typed.isEmpty || String(n).hasPrefix(typed) }
        let valid = { (n: Int) in n >= 1 && count.map { n <= $0 } ?? true }
        var out: [Int] = []
        if let last, valid(last), matches(last) { out.append(last) }
        if let count {
            for n in 1...max(count, 1) where n <= count && matches(n) && n != last {
                out.append(n)
                if out.count >= limit { break }
            }
        } else if let n = Int(typed), valid(n), n != last {
            out.append(n)
        }
        return out
    }

    // 링크가 제목으로 노트를 찾을 때처럼 대소문자를 무시하고 비교한다.
    public static func offersNewNote(_ typed: String, titles: [String]) -> Bool {
        let name = typed.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains(":"), !name.contains("/") else { return false }
        return !titles.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}
