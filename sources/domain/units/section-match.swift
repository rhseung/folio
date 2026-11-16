import Foundation

public enum SectionMatch {
    public static func unit(for title: String, in units: [Unit]) -> Unit? {
        unit(for: title, in: units.map(\.title)).map { units[$0] }
    }

    public static func unit(for title: String, in titles: [String]) -> Int? {
        let found = key(LectureReading.clean(title))
        guard !found.isEmpty else { return nil }
        let keys = titles.map { key(LectureReading.clean($0)) }
        if let exact = keys.firstIndex(of: found) { return exact }
        let holding = keys.indices.filter { i in
            let k = keys[i]
            return k.count > 2 && found.count > 2 && (found.contains(k) || k.contains(found))
        }
        return holding.max { keys[$0].count < keys[$1].count }
    }

    static func key(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func match(_ split: LectureSplit, units: [Unit]) -> LectureSplit {
        var out = split
        for i in out.sections.indices {
            if let unit = unit(for: out.sections[i].title, in: units) {
                out.setUnit(unit.id, of: i, match: .name)
            } else {
                out.makeNew(i)
            }
        }
        return out
    }
}
