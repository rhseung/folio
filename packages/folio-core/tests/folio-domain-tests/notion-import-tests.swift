@testable import FolioDomain
import Foundation
import Testing

struct NotionImportTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)
    let fall = UUID(), credited = UUID(), ec = UUID(), gs = UUID(), aPlus = UUID(), b0 = UUID(), s = UUID()

    var gist: FolderTree {
        func folder(_ name: String, _ children: [FolderTree] = []) -> FolderTree { FolderTree(name: name, content: .folder(children)) }
        return folder("GIST", [folder("2026-3", [folder("EC4207 그래프 이론"), folder("GS2004 선형대수학"), folder("_Admin")])])
    }

    func course(_ title: String, number: String, codes: [UUID], semester: UUID, credits: Double = 3, grade: UUID? = nil) -> NotionExport.CourseRow {
        NotionExport.CourseRow(id: UUID(), title: title, titleEn: nil, number: number, credits: credits, mode: "상대평가", gradeId: grade,
                               absoluteScore: nil, semesterId: semester, codeIds: codes)
    }

    var export: NotionExport {
        var linear = course("선형대수학과 응용", number: "2004-02", codes: [gs], semester: fall)
        linear.policy = .init(caps: [.init(absences: 6, grade: "B0"), .init(absences: 9, grade: "Z")], notes: "원문")
        linear.midterm = .init(start: Date(timeIntervalSince1970: 100), end: nil, location: "C104")
        var graph = course("그래프 이론", number: "4207-01", codes: [ec], semester: fall)
        graph.components = [.init(id: UUID(), name: "Quiz", weight: 10, aggregation: .dropLowest(1), expectedCount: 5,
                                  entries: [.init(id: UUID(), title: "Quiz 1", score: 35, max: 50)])]
        return NotionExport(
            semesters: [
                .init(id: fall, title: "2026 가을학기", start: LocalDate("2026-08-31"), end: nil),
                .init(id: credited, title: "인정학기", start: nil, end: nil),
                .init(id: UUID(), title: "학기명", start: nil, end: nil),
            ],
            grades: [.init(id: aPlus, symbol: "A+", points: 4.5, countsInCredits: true), .init(id: b0, symbol: "B0", points: 3, countsInCredits: true),
                     .init(id: s, symbol: "S", points: nil, countsInCredits: true)],
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
        #expect(Set(result.courseFiles.keys) == ["2026-3/EC4207 그래프 이론", "2026-3/GS2004 선형대수학"])
        #expect(Set(result.transcript.courses.map(\.title)) == ["콜로퀴움", "일반물리학 및 연습 I", "SW 기초와 코딩"])

        let graph = try #require(result.courseFiles["2026-3/EC4207 그래프 이론"])
        #expect(graph.components.first?.aggregation == .dropLowest(1))
        #expect(graph.scores.first?.componentId == graph.components.first?.id)

        let linear = try #require(result.courseFiles["2026-3/GS2004 선형대수학"])
        #expect(linear.policy.attendanceCap == [AttendanceCap(absences: 6, maxGrade: b0)])
        #expect(linear.policy.notes == "원문")
        #expect(linear.exams.first.map { ($0.kind, $0.location) }! == (.midterm, "C104"))
    }

    @Test func creditedTermAndCatalog() throws {
        let result = NotionImporter.convert(export, gist: gist, device: device, now: now)
        let term = try #require(result.transcript.semesters.first { $0.id == credited })
        #expect(term.term == .credited && term.creditedHours == 5 && term.year == 2026)
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
        let first = NotionNotesImporter.merge(dump, into: CourseFile(course: Course(device: device, at: now, title: "그래프 이론")),
                                              existingNotes: [], calendar: calendar, device: device, now: now)
        #expect(first.sessionsAdded == 1)
        let session = first.file.sessions[0]
        #expect(session.name(among: [session]) == "7주차-2" && session.roughNoteId == rough.id && session.reviewNoteId == review.id)
        #expect(first.notes.count == 3)
        #expect(first.notes.first { $0.id == topic.id }?.meta.kind == .topic)
        #expect(first.notes.first { $0.id == review.id }?.meta.sessionId == session.id)

        let again = NotionNotesImporter.merge(dump, into: first.file, existingNotes: Set(first.notes.map(\.id)),
                                              calendar: calendar, device: device, now: now)
        #expect(again.sessionsAdded == 0 && again.notes.isEmpty && again.file.sessions.count == 1)
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
        let r = NotionNotesImporter.merge(dump, into: CourseFile(course: Course(device: UUID(), at: .now, title: "자료구조")),
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
