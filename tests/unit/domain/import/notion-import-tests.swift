import Foundation
import Testing

@testable import FolioDomain

struct NotionImportTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)
    let fall = UUID(), credited = UUID(), ec = UUID(), gs = UUID(), aPlus = UUID(), b0 = UUID(), s = UUID()

    var gist: FolderTree {
        func folder(_ name: String, _ children: [FolderTree] = []) -> FolderTree { FolderTree(name: name, content: .folder(children)) }
        return folder("GIST", [folder("2026-3", [folder("EC4207 그래프 이론"), folder("GS2004 선형대수학"), folder("_Admin")])])
    }

    func course(_ title: String, number: String, codes: [UUID], semester: UUID, credits: Double = 3, grade: UUID? = nil)
        -> NotionExport.CourseRow
    {
        NotionExport.CourseRow(
            id: UUID(), title: title, titleEn: nil, number: number, credits: credits, mode: "상대평가", gradeId: grade,
            absoluteScore: nil, semesterId: semester, codeIds: codes)
    }

    var export: NotionExport {
        var linear = course("선형대수학과 응용", number: "2004-02", codes: [gs], semester: fall)
        linear.policy = .init(caps: [.init(absences: 6, grade: "B0"), .init(absences: 9, grade: "Z")], notes: "원문")
        linear.midterm = .init(start: Date(timeIntervalSince1970: 100), end: nil, location: "C104")
        var graph = course("그래프 이론", number: "4207-01", codes: [ec], semester: fall)
        graph.components = [
            .init(
                id: UUID(), name: "Quiz", weight: 10, aggregation: .dropLowest(1), expectedCount: 5,
                entries: [.init(id: UUID(), title: "Quiz 1", score: 35, max: 50)])
        ]
        return NotionExport(
            semesters: [
                .init(id: fall, title: "2026 가을학기", start: LocalDate("2026-08-31"), end: nil),
                .init(id: credited, title: "인정학기", start: nil, end: nil),
                .init(id: UUID(), title: "학기명", start: nil, end: nil),
            ],
            grades: [
                .init(id: aPlus, symbol: "A+", points: 4.5, countsInCredits: true),
                .init(id: b0, symbol: "B0", points: 3, countsInCredits: true),
                .init(id: s, symbol: "S", points: nil, countsInCredits: true),
            ],
            codes: [.init(id: ec, prefix: "EC", department: "", program: ""), .init(id: gs, prefix: "GS", department: "", program: "")],
            categories: [.init(id: UUID(), name: "전공선택", group: "전공", parentId: nil, minCredits: 33, maxCredits: 39)],
            people: [],
            courses: [
                graph, linear,
                course("콜로퀴움", number: "9331-01", codes: [gs], semester: fall, credits: 0),
                course("일반물리학 및 연습 I", number: "1101", codes: [gs], semester: credited, grade: s),
                course("SW 기초와 코딩", number: "1499", codes: [gs], semester: credited, credits: 2, grade: s),
            ]
        )
    }

    @Test func matchesFoldersBySemesterAndCode() throws {
        let result = NotionImporter.convert(export, gist: gist, device: device, now: now)
        // A course no folder matches gets a new one: credited ones under the term's source, named after the Notion row.
        #expect(
            Set(result.courseFiles.keys) == [
                "2026-3/EC4207 그래프 이론", "2026-3/GS2004 선형대수학", "2026-3/GS9331 콜로퀴움",
                "_Credited/인정학기/GS1101 일반물리학 및 연습 I", "_Credited/인정학기/GS1499 SW 기초와 코딩",
            ])
        #expect(result.transcript.unfiledCourses.isEmpty)

        let graph = try #require(result.courseFiles["2026-3/EC4207 그래프 이론"])
        #expect(graph.components.first?.aggregation == .dropLowest(1))
        #expect(graph.scores.first?.componentId == graph.components.first?.id)

        let linear = try #require(result.courseFiles["2026-3/GS2004 선형대수학"])
        #expect(linear.policy.attendanceCap == [AttendanceCap(absences: 6, maxGrade: b0)])
        #expect(linear.policy.notes == "원문")
        #expect(linear.exams.first.map { ($0.title, $0.folder, $0.location) }! == ("Midterm", "Midterm", "C104"))
    }

    @Test func creditedTermAndCatalog() throws {
        let result = NotionImporter.convert(export, gist: gist, device: device, now: now)
        let term = try #require(result.transcript.semesters.first { $0.id == credited })
        #expect(term.term == .credited && term.creditedHours == 5 && term.year == 2026 && term.source == "인정학기")
        #expect(result.catalog.categories.first?.isMajor == true)
        #expect(result.catalog.grade(s)?.countsInGpa == false)
        #expect(result.catalog.grade(aPlus)?.countsInGpa == true)
    }

    @Test func reportsWhatItCouldNotMap() {
        let warnings = NotionImporter.convert(export, gist: gist, device: device, now: now).warnings
        #expect(warnings.contains { $0.contains("학기명") })
        #expect(warnings.contains { $0.contains("Z") })
    }
}

struct NotionNotesImportTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let calendar = Calendar(identifier: .gregorian)

    func note(_ title: String, _ kind: String?, _ date: String) -> NotionCourseDump.NoteRow {
        .init(id: UUID(), title: title, kind: kind, date: date, file: "notes/x.md")
    }

    @Test func roughAndReviewShareOneSessionAndRerunAddsNothing() {
        let rough = note("7주차-2", "러프", "2026-10-14")
        let review = note("7주차-2 정리", "복습", "2026-10-14")
        let topic = note("6. Projections", nil, "2026-04-01")
        let dump = NotionCourseDump(coursePageId: UUID(), title: "그래프 이론", notes: [review, rough, topic], scores: [], images: [])
        let first = NotionNotesImporter.merge(
            dump, into: CourseFile(course: Course(device: device, at: now, title: "그래프 이론")),
            existingNotes: [], calendar: calendar, device: device, now: now)
        #expect(first.sessionsAdded == 1)
        let session = first.file.sessions[0]
        // The only class known in week 7, so it is 7주차-1 here whatever Notion called it.
        #expect(session.week == 7 && session.roughNoteId == rough.id && session.reviewNoteId == review.id)
        #expect(first.notes.count == 3)
        #expect(first.notes.first { $0.id == topic.id }?.meta.kind == .unit)
        #expect(first.notes.first { $0.id == review.id }?.meta.sessionId == session.id)

        let again = NotionNotesImporter.merge(
            dump, into: first.file, existingNotes: Set(first.notes.map(\.id)),
            calendar: calendar, device: device, now: now)
        #expect(again.sessionsAdded == 0 && again.notes.isEmpty && again.file.sessions.count == 1)
    }

    /// A session that already has a rough note keeps it; the Notion one comes in unlinked, with a warning.
    @Test func aSessionsNoteIsNotTakenByAnImportedOne() {
        let ours = UUID()
        var file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        var session = Session(device: device, at: now, week: 7, date: now)
        session.roughNoteId = ours
        file.sessions = [session]
        var meta = NoteMeta(id: ours)
        meta.kind = .rough
        meta.sessionId = session.id
        file.notes = [NoteEntry(id: ours, device: device, at: now, path: "Notes/7주차-1.md", meta: meta)]
        let rough = note("7주차-1", nil, "2026-10-14")
        let dump = NotionCourseDump(coursePageId: UUID(), title: "그래프 이론", notes: [rough], scores: [], images: [])
        let r = NotionNotesImporter.merge(dump, into: file, existingNotes: [ours], calendar: calendar, device: device, now: now)

        #expect(r.file.sessions[0].roughNoteId == ours)
        #expect(r.notes.first { $0.id == rough.id }?.meta.sessionId == nil)
        #expect(r.warnings.count == 1)
    }

    /// Notion numbered a week's classes in the order they were added, so `7주차-2` can come before `7주차-1`. Two
    /// numbers are still two classes, even when the date order names the first one `7주차-1`.
    @Test func twoNotionNumbersInAWeekStayTwoSessions() {
        let second = note("7주차-2", nil, "2026-10-13")
        let first = note("7주차-1", nil, "2026-10-15")
        let dump = NotionCourseDump(coursePageId: UUID(), title: "그래프 이론", notes: [first, second], scores: [], images: [])
        let r = NotionNotesImporter.merge(
            dump, into: CourseFile(course: Course(device: device, at: now, title: "그래프 이론")),
            existingNotes: [], calendar: calendar, device: device, now: now)
        #expect(r.sessionsAdded == 2 && r.file.sessions.count == 2 && r.warnings.isEmpty)
        #expect(Set(r.notes.compactMap(\.meta.sessionId)) == Set(r.file.sessions.map(\.id)))
    }

    /// A note imported before and unlinked since stays unlinked; importing again doesn't set the session's side alone.
    @Test func anImportedNoteThatWasUnlinkedStaysSo() {
        let rough = note("7주차-2", nil, "2026-10-14")
        let dump = NotionCourseDump(coursePageId: UUID(), title: "그래프 이론", notes: [rough], scores: [], images: [])
        let first = NotionNotesImporter.merge(
            dump, into: CourseFile(course: Course(device: device, at: now, title: "그래프 이론")),
            existingNotes: [], calendar: calendar, device: device, now: now)
        var file = first.file
        file.forgetNote(rough.id)
        let again = NotionNotesImporter.merge(dump, into: file, existingNotes: [rough.id], calendar: calendar, device: device, now: now)
        #expect(again.file.sessions[0].roughNoteId == nil && again.warnings.isEmpty)
    }

    @Test func scoresGoUnderTheirTopLevelComponent() {
        let quiz = NotionCourseDump.ScoreRow(id: UUID(), name: "Quiz", weight: 10, score: nil, max: nil, parentId: nil)
        let q1 = NotionCourseDump.ScoreRow(id: UUID(), name: "Quiz 1", weight: nil, score: 35, max: 50, parentId: quiz.id)
        let q2 = NotionCourseDump.ScoreRow(id: UUID(), name: "Quiz 2", weight: nil, score: nil, max: 50, parentId: quiz.id)
        let mid = NotionCourseDump.ScoreRow(id: UUID(), name: "Midterm", weight: 35, score: 80, max: 100, parentId: nil)
        var file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        file.components = [GradeComponent(device: device, at: now, name: "quiz", weight: 10, aggregation: .dropLowest(1))]
        let dump = NotionCourseDump(coursePageId: UUID(), title: "", notes: [], scores: [quiz, q1, q2, mid], images: [])
        let r = NotionNotesImporter.merge(dump, into: file, existingNotes: [], calendar: calendar, device: device, now: now)

        #expect(r.componentsAdded == 1)
        #expect(r.file.components[0].aggregation == .dropLowest(1))
        #expect(r.file.scores.map(\.title) == ["Quiz 1", "Midterm"])
        #expect(r.file.scores[0].componentId == file.components[0].id)
        let again = NotionNotesImporter.merge(dump, into: r.file, existingNotes: [], calendar: calendar, device: device, now: now)
        #expect(again.scoresAdded == 0 && again.componentsAdded == 0)
    }
}

struct NotionCleanupTests {
    @Test func titlesLoseEscapesAndTags() {
        #expect(NotionNotesImporter.clean("1\\. Numbers & Codes") == "1. Numbers & Codes")
        #expect(NotionNotesImporter.clean("<p>\n Worksheet\n</p>") == "Worksheet")
        #expect(NotionNotesImporter.clean("3주차-2 정리") == "3주차-2 정리")
    }

    @Test func pointWeightsAreScaledToPercent() {
        let rows = [("Assignment", 600.0), ("Midterm", 200.0), ("Final", 200.0)].map {
            NotionCourseDump.ScoreRow(id: UUID(), name: $0.0, weight: $0.1, score: nil, max: nil, parentId: nil)
        }
        let dump = NotionCourseDump(coursePageId: UUID(), title: "", notes: [], scores: rows, images: [])
        let r = NotionNotesImporter.merge(
            dump, into: CourseFile(course: Course(device: UUID(), at: .now, title: "자료구조")),
            existingNotes: [], calendar: .current, device: UUID(), now: .now)
        #expect(r.file.components.map(\.weight) == [60, 20, 20])
    }
}

@Test func parentIsNotAddedWhenItsChildrenAreAlreadyComponents() {
    let lessons = NotionCourseDump.ScoreRow(id: UUID(), name: "Lessons", weight: 60, score: nil, max: nil, parentId: nil)
    let quiz = NotionCourseDump.ScoreRow(id: UUID(), name: "Pre-lab Quiz", weight: 20, score: 8, max: 10, parentId: lessons.id)
    var file = CourseFile(course: Course(device: UUID(), at: .now, title: "일반화학실험"))
    file.components = [GradeComponent(id: quiz.id, device: UUID(), at: .now, name: "Pre-lab Quiz", weight: 20)]
    let dump = NotionCourseDump(coursePageId: UUID(), title: "", notes: [], scores: [lessons, quiz], images: [])
    let r = NotionNotesImporter.merge(dump, into: file, existingNotes: [], calendar: .current, device: UUID(), now: .now)
    #expect(r.componentsAdded == 0 && r.file.components.map(\.weight) == [20])
    #expect(r.file.scores.map(\.componentId) == [quiz.id])
}
