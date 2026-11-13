import Foundation

/// What the edit view's link completion (#31) offers and in what order. The app asks the search index and reads the
/// files; these rules decide what of it shows.
public enum LinkCandidates {
    /// The course being written in first, each part in the order the search ranked it; the note being written isn't
    /// offered, since a link to it from itself goes nowhere.
    public static func order(_ hits: [SearchHit], course: UUID, excluding own: UUID? = nil) -> [SearchHit] {
        let kept = hits.filter { $0.item.id != own }
        return kept.filter { $0.item.courseId == course } + kept.filter { $0.item.courseId != course }
    }

    /// The pages offered after `#page=`, whose number starts with what's typed: the page last seen first, then the
    /// rest from the first. Without a page count (a file not downloaded yet), the last page seen and the typed number.
    /// `last` and the result are 1-based.
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

    /// Whether a new note named `typed` is offered: something is typed, no note of the course has that title (as
    /// links find titles, ignoring case), and it isn't a link by ID being written.
    public static func offersNewNote(_ typed: String, titles: [String]) -> Bool {
        let name = typed.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains(":"), !name.contains("/") else { return false }
        return !titles.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}
