import Foundation

public enum LinkCandidates {
    // 검색은 대소문자를 가리지 않아 `Matrix`를 쳐도 `matrix` 노트가 앞에 설 수 있다. 메뉴는 맨 위 후보를 넣으므로
    // 친 글자와 대소문자까지 같은 제목을 그 과목 묶음의 맨 앞에 세운다.
    public static func order(_ hits: [SearchHit], typed: String = "", course: UUID, excluding own: UUID? = nil) -> [SearchHit] {
        let kept = hits.filter { $0.item.id != own }
        let exact = { (hit: SearchHit) in !typed.isEmpty && hit.item.title == typed }
        let group = { (hits: [SearchHit]) in hits.filter(exact) + hits.filter { !exact($0) } }
        return group(kept.filter { $0.item.courseId == course }) + group(kept.filter { $0.item.courseId != course })
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
