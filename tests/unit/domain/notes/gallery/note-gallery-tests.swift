import FolioCore
import FolioDomain
import Foundation
import Testing

struct NoteGalleryTests {
    let device = UUID()
    let settings = Settings()
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }

    // 2026-11-18(수) 정오. 이번 주는 11/16(월) 새벽 4시에 시작한다.
    var now: Date { at(2026, 11, 18, 12, 0) }

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? .distantPast
    }

    func item(_ title: String, _ meta: NoteMeta = NoteMeta(), folder: String = "", modified: Date? = nil, created: Date? = nil)
        -> NoteGallery.Item
    {
        NoteGallery.Item(
            url: URL(filePath: "/Notes/\(title).md"), title: title, meta: meta, folder: folder, created: created ?? now,
            modified: modified ?? now)
    }

    func sections(_ items: [NoteGallery.Item], _ grouping: NoteGrouping, sort: NoteSort = .modified, file: CourseFile? = nil)
        -> [NoteGallery.Section]
    {
        NoteGallery.sections(
            items, grouping: grouping, sort: sort, in: file ?? CourseFile(course: Course(device: device, at: now, title: "")), now: now,
            settings: settings, calendar: calendar)
    }

    func span(_ a: String, _ b: String) -> ClosedRange<LocalDate>? {
        guard let a = LocalDate(a), let b = LocalDate(b) else { return nil }
        return a...b
    }

    @Test func eachKindOffersItsOwnGroupingsWithTheFirstAsDefault() {
        #expect(NoteGrouping.options(for: nil) == [.date, .kind, .none])
        #expect(NoteGrouping.options(for: .classes) == [.week, .unit, .date])
        #expect(NoteGrouping.options(for: .units) == [.unit])
        #expect(NoteGrouping.options(for: .exams) == [.exam])
        #expect(NoteGrouping.options(for: .free) == [.folder, .tag, .date])
    }

    @Test func datesFallIntoThisWeekLastWeekTwoWeeksAgoAndMonthsByStudyDay() {
        let notes = [
            item("월 4시", modified: at(2026, 11, 16, 4, 0)),
            item("월 3시 59분", modified: at(2026, 11, 16, 3, 59)),
            item("지난 월 4시", modified: at(2026, 11, 9, 4, 0)),
            item("지난 월 3시 59분", modified: at(2026, 11, 9, 3, 59)),
            item("2주 전 월 3시 59분", modified: at(2026, 11, 2, 3, 59)),
            item("10월", modified: at(2026, 10, 20, 12, 0)),
            item("오늘", modified: now),
        ]
        let got = sections(notes, .date)

        #expect(
            got.map(\.heading) == [.thisWeek, .lastWeek, .twoWeeksAgo, .month(year: 2026, month: 11), .month(year: 2026, month: 10)])
        #expect(got[0].items.map(\.title) == ["오늘", "월 4시"])
        #expect(got[1].items.map(\.title) == ["월 3시 59분", "지난 월 4시"])
        #expect(got[2].items.map(\.title) == ["지난 월 3시 59분"])
        #expect(got[3].items.map(\.title) == ["2주 전 월 3시 59분"])
        #expect(got.map(\.opensFirst) == [true, true, false, false, false])
        #expect(got[0].span == span("2026-11-16", "2026-11-22"))
        #expect(got[1].span == span("2026-11-09", "2026-11-15"))
        #expect(got[3].span == nil)
    }

    @Test func dateGroupsFollowCreationWhenSortedByCreation() {
        let note = item("노트", modified: now, created: at(2026, 10, 1, 12, 0))
        #expect(sections([note], .date, sort: .created).map(\.heading) == [.month(year: 2026, month: 10)])
        #expect(sections([note], .date).map(\.heading) == [.thisWeek])
    }

    @Test func aNoteOverTwoUnitsShowsInBothAndUnlinkedNotesComeLast() {
        let matching = Unit(device: device, at: now, title: "매칭", order: 0)
        let hall = Unit(device: device, at: now, title: "König–Hall", order: 1)
        let coloring = Unit(device: device, at: now, title: "채색", order: 2)
        var quiz = Exam(device: device, at: now, title: "Quiz 3", start: at(2026, 11, 24, 10, 0))
        quiz.scopeUnitIds = [hall.id]
        var midterm = Exam(device: device, at: now, title: "중간고사", start: at(2026, 10, 20, 10, 0))
        midterm.scopeUnitIds = [coloring.id, matching.id]
        let file = CourseFile(
            course: Course(device: device, at: now, title: ""), units: [coloring, hall, matching], exams: [quiz, midterm])
        let notes = [
            item("복습 11/9–11/11", NoteMeta(kind: .review, unitIds: [hall.id, matching.id])),
            item("채색 러프", NoteMeta(kind: .rough, unitIds: [coloring.id])),
            item("단원 없는 러프", NoteMeta(kind: .rough)),
        ]
        let got = sections(notes, .unit, file: file)

        #expect(got.map(\.heading) == [.unit(matching.id), .unit(hall.id), .unit(coloring.id), .noUnit])
        #expect(got[0].items.map(\.title) == ["복습 11/9–11/11"])
        #expect(got[1].items.map(\.title) == ["복습 11/9–11/11"])
        #expect(got.map(\.opensFirst) == [false, true, false, false])
        #expect(got.map(\.scope?.title) == ["중간고사", "Quiz 3", "중간고사", nil])
    }

    @Test func unitsAllOpenWhenNoExamIsAhead() {
        let unit = Unit(device: device, at: now, title: "매칭", order: 0)
        let file = CourseFile(course: Course(device: device, at: now, title: ""), units: [unit])
        let got = sections([item("러프", NoteMeta(kind: .rough, unitIds: [unit.id])), item("자유")], .unit, file: file)
        #expect(got.map(\.opensFirst) == [true, true])
    }

    @Test func classWeeksRunNewestFirstAndOpenThisAndLastWeek() {
        let notes = (0..<4).map { item("러프 \($0)", NoteMeta(kind: .rough)) } + [item("회차 없음", NoteMeta(kind: .rough))]
        let days = [at(2026, 11, 16, 10, 0), at(2026, 11, 11, 10, 0), at(2026, 11, 4, 10, 0), at(2026, 11, 18, 10, 0)]
        let weeks = [11, 10, 9, 11]
        var sessions: [Session] = []
        for i in 0..<4 {
            var s = Session(device: device, at: now, week: weeks[i], date: days[i])
            s.roughNoteId = notes[i].meta.id
            sessions.append(s)
        }
        let file = CourseFile(course: Course(device: device, at: now, title: ""), sessions: sessions)
        let got = sections(notes, .week, sort: .course, file: file)

        #expect(got.map(\.heading) == [.week(11), .week(10), .week(9), .noSession])
        #expect(got[0].items.map(\.title) == ["러프 0", "러프 3"])
        #expect(got.map(\.opensFirst) == [true, true, false, false])
        #expect(got[2].span == span("2026-11-02", "2026-11-08"))
    }

    @Test func courseOrderPutsDatedNotesFirstThenUnitsThenFreeNotes() {
        let first = Unit(device: device, at: now, title: "첫 단원", order: 0)
        let second = Unit(device: device, at: now, title: "둘째 단원", order: 1)
        let exam = Exam(device: device, at: now, title: "중간", start: at(2026, 11, 12, 10, 0))
        let rough = item("러프", NoteMeta(kind: .rough))
        var session = Session(device: device, at: now, week: 1, date: at(2026, 11, 10, 10, 0))
        session.roughNoteId = rough.meta.id
        let file = CourseFile(
            course: Course(device: device, at: now, title: ""), units: [first, second], sessions: [session], exams: [exam])
        let notes = [
            item("가 자유"), item("둘째 단원 노트", NoteMeta(kind: .unit, unitIds: [second.id])),
            item("중간 정리", NoteMeta(kind: .examSummary, examId: exam.id)), rough,
            item("첫 단원 노트", NoteMeta(kind: .unit, unitIds: [first.id])),
        ]

        #expect(
            NoteGallery.sorted(notes, by: .course, in: file).map(\.title) == ["러프", "중간 정리", "첫 단원 노트", "둘째 단원 노트", "가 자유"])
        #expect(NoteGallery.sorted(notes, by: .title, in: file).map(\.title).first == "가 자유")
    }

    @Test func recentEditsComeFirstAndTiesFallBackToTitle() {
        let notes = [item("나", modified: now - 60), item("다", modified: now), item("가", modified: now - 60)]
        #expect(
            NoteGallery.sorted(notes, by: .modified, in: CourseFile(course: Course(device: device, at: now, title: ""))).map(\.title) == [
                "다", "가", "나",
            ])
    }

    @Test func kindsFoldersAndTagsEachMakeTheirOwnGroups() {
        let notes = [
            item("자유 A", NoteMeta(kind: .free, tags: ["증명", "흐름"]), folder: "정리"),
            item("자유 B", NoteMeta(kind: .free), folder: ""),
            item("단원", NoteMeta(kind: .unit)),
            item("러프", NoteMeta(kind: .rough)),
        ]
        #expect(sections(notes, .kind).map(\.heading) == [.kind(.classes), .kind(.units), .kind(.free)])
        #expect(sections(notes, .folder).map(\.heading) == [.folder(""), .folder("정리")])
        #expect(sections(notes, .tag).map(\.heading) == [.tag("증명"), .tag("흐름"), .noTag])
        #expect(sections(notes, .none).map(\.heading) == [nil])
        #expect(sections([], .date).isEmpty)
    }

    @Test func examGroupsRunByStartWithLooseSummariesLast() {
        let later = Exam(device: device, at: now, title: "기말", start: at(2026, 12, 15, 10, 0))
        let sooner = Exam(device: device, at: now, title: "중간", start: at(2026, 10, 20, 10, 0))
        let file = CourseFile(course: Course(device: device, at: now, title: ""), exams: [later, sooner])
        let notes = [
            item("기말 정리", NoteMeta(kind: .examSummary, examId: later.id)), item("정리", NoteMeta(kind: .examSummary)),
            item("중간 정리", NoteMeta(kind: .examSummary, examId: sooner.id)),
        ]
        #expect(sections(notes, .exam, file: file).map(\.heading) == [.exam(sooner.id), .exam(later.id), .noExam])
    }

    @Test func cardsLeaveOutWhatTheGroupAlreadySays() {
        let unit = Unit(device: device, at: now, title: "매칭", order: 0)
        let exam = Exam(device: device, at: now, title: "중간")
        let review = NoteMeta(kind: .review, unitIds: [unit.id], tags: ["증명"])
        var session = Session(device: device, at: now, week: 1, date: now)
        session.reviewNoteId = review.id
        let file = CourseFile(course: Course(device: device, at: now, title: ""), units: [unit], sessions: [session], exams: [exam])

        let byDate = NoteFacets(of: review, in: file, grouping: .date)
        #expect(byDate.sessions.map(\.id) == [session.id] && byDate.units.map(\.id) == [unit.id] && byDate.tags == ["증명"])
        let byUnit = NoteFacets(of: review, in: file, grouping: .unit)
        #expect(byUnit.sessions.map(\.id) == [session.id] && byUnit.units.isEmpty)
        #expect(NoteFacets(of: review, in: file, grouping: .tag).tags.isEmpty)

        let summary = NoteMeta(kind: .examSummary, examId: exam.id)
        #expect(NoteFacets(of: summary, in: file, grouping: .date).exam?.id == exam.id)
        #expect(NoteFacets(of: summary, in: file, grouping: .exam).isEmpty)
    }
}
