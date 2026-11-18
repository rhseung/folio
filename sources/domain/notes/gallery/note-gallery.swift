import FolioCore
import Foundation

// 노트 페이지의 카드 격자다. 고른 종류의 노트를 묶기대로 접히는 묶음으로 나누고 묶음 안을 정렬한다.
public enum NoteGallery {
    public struct Item: Sendable, Equatable {
        public var url: URL
        public var title: String
        public var meta: NoteMeta
        // Notes 폴더 안의 폴더 경로다. 맨 위는 빈 문자열이다.
        public var folder: String
        public var created: Date
        public var modified: Date

        public init(url: URL, title: String, meta: NoteMeta, folder: String, created: Date, modified: Date) {
            self.url = url
            self.title = title
            self.meta = meta
            self.folder = folder
            self.created = created
            self.modified = modified
        }
    }

    public enum Heading: Hashable, Sendable {
        case thisWeek, lastWeek, twoWeeksAgo
        case month(year: Int, month: Int)
        case week(Int)
        case noSession
        case unit(UUID)
        case noUnit
        case exam(UUID)
        case noExam
        case kind(NoteGroup)
        case folder(String)
        case tag(String)
        case noTag

        // 접은 묶음을 기기에 기억하는 열쇠다.
        public var key: String {
            switch self {
            case .thisWeek: "this-week"
            case .lastWeek: "last-week"
            case .twoWeeksAgo: "two-weeks-ago"
            case .month(let y, let m): "month-\(y)-\(m)"
            case .week(let n): "week-\(n)"
            case .noSession: "no-session"
            case .unit(let id): "unit-\(id.uuidString)"
            case .noUnit: "no-unit"
            case .exam(let id): "exam-\(id.uuidString)"
            case .noExam: "no-exam"
            case .kind(let g): "kind-\(g)"
            case .folder(let f): "folder-\(f)"
            case .tag(let t): "tag-\(t)"
            case .noTag: "no-tag"
            }
        }
    }

    public struct Section: Sendable, Identifiable {
        // 없으면 머리 없는 한 묶음이다(묶지 않음, 찾기).
        public var heading: Heading?
        public var items: [Item]
        // 주 단위 머리가 보이는 날짜 범위다.
        public var span: ClosedRange<LocalDate>?
        // 단원 머리가 보이는, 이 단원이 든 가장 가까운 시험이다.
        public var scope: Exam?
        public var opensFirst: Bool

        public var id: String { heading?.key ?? "all" }

        init(heading: Heading?, items: [Item], span: ClosedRange<LocalDate>? = nil, scope: Exam? = nil, opensFirst: Bool = true) {
            self.heading = heading
            self.items = items
            self.span = span
            self.scope = scope
            self.opensFirst = opensFirst
        }
    }

    public static func sections(
        _ items: [Item], grouping: NoteGrouping, sort: NoteSort, in file: CourseFile, now: Date, settings: Settings,
        calendar: Calendar
    ) -> [Section] {
        guard !items.isEmpty else { return [] }
        let order = { (list: [Item]) in sorted(list, by: sort, in: file) }
        let today = settings.studyDay(of: now, calendar: calendar)
        let monday = Self.monday(of: today)
        let day = { (date: Date) in settings.studyDay(of: date, calendar: calendar) }

        switch grouping {
        case .none:
            return [Section(heading: nil, items: order(items))]

        case .date:
            let dated = { (item: Item) in day(sort == .created ? item.created : item.modified) }
            let buckets = Dictionary(grouping: items) { bucket(of: dated($0), monday: monday) }
            return buckets.keys.sorted { rank($0) < rank($1) }.map { heading in
                Section(
                    heading: heading, items: order(buckets[heading] ?? []), span: span(of: heading, monday: monday),
                    opensFirst: heading == .thisWeek || heading == .lastWeek)
            }

        case .week:
            var weeks: [Int: [Item]] = [:]
            var starts: [Int: LocalDate] = [:]
            var loose: [Item] = []
            for item in items {
                guard let last = file.sessions(pointingAt: item.meta.id).last else {
                    loose.append(item)
                    continue
                }
                weeks[last.week, default: []].append(item)
                let start = Self.monday(of: day(last.date))
                starts[last.week] = min(starts[last.week] ?? start, start)
            }
            let recent = monday.adding(days: -7)
            return weeks.keys.sorted(by: >).map { week in
                let start = starts[week] ?? monday
                return Section(
                    heading: .week(week), items: order(weeks[week] ?? []), span: start...start.adding(days: 6), opensFirst: start >= recent)
            } + (loose.isEmpty ? [] : [Section(heading: .noSession, items: order(loose), opensFirst: false)])

        case .unit:
            let upcoming = file.exams.filter { !$0.isOver(now: now, today: today, calendar: calendar) }
                .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            let past = file.exams.filter { e in !upcoming.contains { $0.id == e.id } }.sorted {
                ($0.start ?? .distantPast) > ($1.start ?? .distantPast)
            }
            let reach = { (exam: Exam) in
                exam.scopeUnitIds.reduce(into: Set<UUID>()) { $0.formUnion(UnitTree.subtree(of: $1, in: file.units)) }
            }
            let next = upcoming.first { !$0.scopeUnitIds.isEmpty }.map(reach)
            let known = Set(file.units.map(\.id))
            var sections = UnitTree.outline(file.units).map(\.unit).compactMap { unit -> Section? in
                let members = items.filter { $0.meta.unitIds.contains(unit.id) }
                guard !members.isEmpty else { return nil }
                return Section(
                    heading: .unit(unit.id), items: order(members), scope: (upcoming + past).first { reach($0).contains(unit.id) },
                    opensFirst: next?.contains(unit.id) ?? true)
            }
            let loose = items.filter { !$0.meta.unitIds.contains(where: known.contains) }
            if !loose.isEmpty { sections.append(Section(heading: .noUnit, items: order(loose), opensFirst: next == nil)) }
            return sections

        case .exam:
            let exams = file.exams.sorted { a, b in
                a.start != b.start
                    ? (a.start ?? .distantFuture) < (b.start ?? .distantFuture)
                    : a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
            let sections = exams.compactMap { exam -> Section? in
                let members = items.filter { $0.meta.examId == exam.id }
                return members.isEmpty ? nil : Section(heading: .exam(exam.id), items: order(members))
            }
            let loose = items.filter { item in !exams.contains { $0.id == item.meta.examId } }
            return sections + (loose.isEmpty ? [] : [Section(heading: .noExam, items: order(loose))])

        case .kind:
            return [NoteGroup.classes, .units, .exams, .free].compactMap { group in
                let members = items.filter { NoteGroup($0.meta.kind) == group }
                return members.isEmpty ? nil : Section(heading: .kind(group), items: order(members))
            }

        case .folder:
            let folders = Dictionary(grouping: items, by: \.folder)
            return folders.keys.sorted { a, b in a.isEmpty != b.isEmpty ? a.isEmpty : a.localizedStandardCompare(b) == .orderedAscending }
                .map { Section(heading: .folder($0), items: order(folders[$0] ?? [])) }

        case .tag:
            let tags = Set(items.flatMap(\.meta.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let loose = items.filter(\.meta.tags.isEmpty)
            return tags.map { tag in Section(heading: .tag(tag), items: order(items.filter { $0.meta.tags.contains(tag) })) }
                + (loose.isEmpty ? [] : [Section(heading: .noTag, items: order(loose))])
        }
    }

    public static func sorted(_ items: [Item], by sort: NoteSort, in file: CourseFile) -> [Item] {
        func byTitle(_ a: Item, _ b: Item) -> Bool { a.title.localizedStandardCompare(b.title) == .orderedAscending }
        switch sort {
        case .modified: return items.sorted { $0.modified != $1.modified ? $0.modified > $1.modified : byTitle($0, $1) }
        case .created: return items.sorted { $0.created != $1.created ? $0.created > $1.created : byTitle($0, $1) }
        case .title: return items.sorted(by: byTitle)
        case .course:
            let outline = UnitTree.outline(file.units).map(\.unit.id)
            // 회차와 시험은 날짜로 함께 놓고, 단원 노트는 그 뒤에 단원 목록 순서로, 자유 노트는 맨 끝에 둔다. 날짜와 단원
            // 목록의 자리는 서로 견줄 수 없는 값이라 한 줄로 섞지 않는다.
            let key = { (item: Item) -> (Int, Double) in
                switch NoteGroup(item.meta.kind) {
                case .classes:
                    return (0, file.sessions(pointingAt: item.meta.id).first?.date.timeIntervalSinceReferenceDate ?? .infinity)
                case .exams:
                    return (0, file.exams.first { $0.id == item.meta.examId }?.start?.timeIntervalSinceReferenceDate ?? .infinity)
                case .units:
                    return (1, item.meta.unitIds.compactMap { outline.firstIndex(of: $0) }.min().map(Double.init) ?? .infinity)
                case .free:
                    return (2, 0)
                }
            }
            return items.map { (item: $0, key: key($0)) }.sorted { a, b in a.key != b.key ? a.key < b.key : byTitle(a.item, b.item) }.map(
                \.item)
        }
    }

    // 주는 월요일에 시작한다. 날짜는 공부일이라 월요일 새벽 4시 전은 지난주다.
    static func monday(of day: LocalDate) -> LocalDate {
        let utc = LocalDate.utc
        guard let date = day.date(in: utc) else { return day }
        return day.adding(days: -(utc.isoWeekday(of: date) - 1))
    }

    static func bucket(of day: LocalDate, monday: LocalDate) -> Heading {
        if day >= monday { return .thisWeek }
        if day >= monday.adding(days: -7) { return .lastWeek }
        if day >= monday.adding(days: -14) { return .twoWeeksAgo }
        return .month(year: day.year, month: day.month)
    }

    static func span(of heading: Heading, monday: LocalDate) -> ClosedRange<LocalDate>? {
        switch heading {
        case .thisWeek: monday...monday.adding(days: 6)
        case .lastWeek: monday.adding(days: -7)...monday.adding(days: -1)
        case .twoWeeksAgo: monday.adding(days: -14)...monday.adding(days: -8)
        default: nil
        }
    }

    static func rank(_ heading: Heading) -> Int {
        switch heading {
        case .thisWeek: Int.min
        case .lastWeek: Int.min + 1
        case .twoWeeksAgo: Int.min + 2
        case .month(let y, let m): -(y * 12 + m)
        default: 0
        }
    }
}
