import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct ActionTests {
    static let graphTheory = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
    }

    @discardableResult
    func run(_ action: some Action, dryRun: Bool = false) throws -> ActionContext {
        let ctx = ActionContext(gist: gist, device: device, now: now, dryRun: dryRun)
        try action.run(ctx)
        return ctx
    }

    func file() throws -> CourseFile { try ActionContext(gist: gist, device: device).file(Self.graphTheory) }

    @Test func aPathFieldNamesAFile() {
        let note = NoteRemove.spec.fields.first { $0.name == "note" }
        #expect(note?.ref == "NotePath")
        #expect(note?.type == "String")
    }

    /// The app enables its buttons with a dry run over the documents it shows, which may be ahead of the disk.
    @Test func aCheckReadsThePreloadedDocuments() throws {
        let disk = ActionContext(gist: gist, device: device)
        var doc = try disk.store(Self.graphTheory).load()
        let component = GradeComponent(device: device, at: now, name: "중간고사", weight: 30, order: 99, aggregation: .single)
        doc.model.components.append(component)
        doc.model.scores.append(ScoreEntry(device: device, at: now, componentId: component.id, title: "", score: 11, max: 20))
        let check = ActionContext(gist: gist, device: device, now: now, dryRun: true)
        check.preload(courses: [doc], transcript: try disk.transcript(), catalog: try disk.catalog(), settings: try disk.settings())
        #expect(throws: ActionError.self) { try ScoreAdd(course: Self.graphTheory, component: component.id, score: 12, max: 20).run(check) }
    }

    @Test func aDryRunReportsTheChangeAndWritesNothing() throws {
        let url = try ActionContext(gist: gist, device: device).store(Self.graphTheory).courseFileURL
        let before = try Data(contentsOf: url)
        let id = UUID()
        let ctx = try run(SessionAdd(id: id, course: Self.graphTheory, date: now), dryRun: true)
        #expect(try Data(contentsOf: url) == before)
        #expect(ctx.changes.contains { $0.kind == .added && $0.item == "sessions/\(id.uuidString)" })
        #expect(ctx.made == id)
    }

    @Test func aSessionANotePointsAtStays() throws {
        let kept = UUID(), free = UUID()
        try run(SessionAdd(id: kept, course: Self.graphTheory, date: now))
        try run(SessionAdd(id: free, course: Self.graphTheory, date: now.addingTimeInterval(86_400)))
        try run(SessionNote(course: Self.graphTheory, session: kept, kind: .review))

        #expect(try file().sessions.first { $0.id == kept }?.reviewNoteUnfinished == true)
        #expect(throws: ActionError.self) { try run(SessionRemove(course: Self.graphTheory, sessions: [kept, free])) }
        #expect(try file().sessions.count == 2)
        try run(SessionRemove(course: Self.graphTheory, sessions: [free]))
        #expect(try file().sessions.map(\.id) == [kept])
    }

    @Test func aMakeupHeldOnlineKeepsItsEndAndLink() throws {
        let id = UUID()
        let end = now.addingTimeInterval(75 * 60)
        try run(SessionAdd(id: id, course: Self.graphTheory, date: now, end: end, link: " https://zoom.us/j/123 "))
        var s = try #require(try file().sessions.first { $0.id == id })
        #expect(s.end == end && s.link == "https://zoom.us/j/123")

        try run(SessionSet(course: Self.graphTheory, session: id, link: .set(nil)))
        s = try #require(try file().sessions.first { $0.id == id })
        #expect(s.link == nil && s.end == end)

        // Moved a day on, its own end moves with it.
        let later = now.addingTimeInterval(86_400)
        try run(SessionSet(course: Self.graphTheory, session: id, date: .set(later)))
        s = try #require(try file().sessions.first { $0.id == id })
        #expect(s.date == later && s.end == end.addingTimeInterval(86_400))

        #expect(throws: ActionError.self) { try run(SessionSet(course: Self.graphTheory, session: id, link: .set("813643"))) }
        #expect(throws: ActionError.self) { try run(SessionSet(course: Self.graphTheory, session: id, end: .set(now))) }
    }

    /// An absence known ahead makes its session in the same write, so a refused one leaves no session behind.
    @Test func anAbsenceAheadMakesItsSessionOrNothing() throws {
        let id = UUID()
        try run(SessionAdd(id: id, course: Self.graphTheory, date: now, attendance: .absent))
        #expect(try file().attendance.first { $0.sessionId == id }?.state == .absent)

        let before = try file().sessions.count
        #expect(throws: ActionError.self) {
            try run(SessionAdd(course: Self.graphTheory, date: now.addingTimeInterval(86_400), cancelled: true, attendance: .absent))
        }
        #expect(try file().sessions.count == before)

        // Present is the default and stored as nothing.
        let present = UUID()
        try run(SessionAdd(id: present, course: Self.graphTheory, date: now.addingTimeInterval(2 * 86_400), attendance: .present))
        #expect(try !file().attendance.contains { $0.sessionId == present })
    }

    /// One way to skip: from a list nothing was open, so no time; from the review screen the time it was open is study.
    @Test func aSkipCountsOnlyTheTimeTheUnitWasOpen() throws {
        let a = UUID(), b = UUID()
        let log = try ActionContext(gist: gist, device: device).store(Self.graphTheory).log
        try run(ReviewSkip(units: [.init(course: Self.graphTheory, unit: a)]))
        try run(ReviewSkip(units: [.init(course: Self.graphTheory, unit: b)], start: now.addingTimeInterval(-90), end: now))
        let reviews = try log.readAll().events(ReviewEvent.self).map(\.event)
        #expect(reviews.allSatisfy { $0.result == .skip })
        #expect(Dictionary(uniqueKeysWithValues: reviews.map { ($0.unitId, $0.seconds) }) == [a: 0, b: 90])
        #expect(try log.readAll().events(StudySessionEvent.self).map(\.event)
            == [StudySessionEvent(courseId: Self.graphTheory, start: now.addingTimeInterval(-90), end: now, screen: "review")])

        let both = [ReviewSkip.Target(course: Self.graphTheory, unit: a), .init(course: Self.graphTheory, unit: b)]
        #expect(throws: ActionError.self) { try run(ReviewSkip(units: both, start: now, end: now)) }
        #expect(throws: ActionError.self) { try run(ReviewSkip(units: [both[0]], start: now)) }
        #expect(throws: ActionError.self) { try run(ReviewSkip(units: [both[0]], start: now, end: now.addingTimeInterval(-1))) }
        #expect(throws: ActionError.self) { try run(ReviewRecord(course: Self.graphTheory, unit: a, result: .skip, start: now, end: now)) }
        #expect(try log.readAll().events(ReviewEvent.self).count == 2)
    }

    @Test func aClassTimeLinkIsTrimmedAndABlankOneIsNone() throws {
        try run(CourseSet(course: Self.graphTheory, [.schedule([
            ClassTime(weekday: 1, startMinute: 600, endMinute: 675, link: " "),
            ClassTime(weekday: 3, startMinute: 600, endMinute: 675, link: " https://zoom.us/j/1 "),
        ])]))
        #expect(try file().course.schedule.map(\.link) == [nil, "https://zoom.us/j/1"])
    }

    /// The folder is named now but made by the first file, so an exam with no files leaves no empty folder behind.
    @Test func aNewExamNamesItsFolderWithoutMakingIt() throws {
        let ctx = try run(ExamAdd(course: Self.graphTheory, title: "Quiz1", start: now))
        #expect(!ctx.changes.contains { $0.path.hasSuffix("/") })
        let exam = try #require(try file().exams.first { $0.id == ctx.made })
        #expect(exam.folder == "Quiz1")
        #expect(!FileManager.default.fileExists(atPath: try ActionContext(gist: gist, device: device).store(Self.graphTheory).fileURL("Exams/Quiz1").path))
    }

    @Test func aNoteChangedElsewhereIsNotOverwritten() throws {
        let store = try ActionContext(gist: gist, device: device).store(Self.graphTheory)
        let path = "Notes/09-08(화) 매칭.md"
        let read = try String(contentsOf: store.fileURL(path), encoding: .utf8)
        try run(NoteWrite(course: Self.graphTheory, note: path, text: read + "\n바깥에서 고침", expected: read))
        #expect(throws: ActionError.conflict("노트가 다른 곳에서 바뀌었습니다: \(path)")) {
            try run(NoteWrite(course: Self.graphTheory, note: path, text: "덮어쓰기", expected: read))
        }
        #expect(try String(contentsOf: store.fileURL(path), encoding: .utf8).hasSuffix("바깥에서 고침"))
    }

    @Test func aNoteEditReplacesInOrderAndAppendsOnANewLine() throws {
        let store = try ActionContext(gist: gist, device: device).store(Self.graphTheory)
        let path = "Notes/09-08(화) 매칭.md"
        let url = store.fileURL(path)
        try "# 매칭\n\n짝짓기는 간선 집합이다".write(to: url, atomically: true, encoding: .utf8)
        let edits = [NoteEdit.Replacement(old: "짝짓기는", new: "매칭은"), NoteEdit.Replacement(old: "# 매칭\n\n매칭", new: "# 매칭\n\n최대 매칭")]
        let ctx = try run(NoteEdit(course: Self.graphTheory, note: path, replacements: edits, append: "- 질문"))
        #expect(try String(contentsOf: url, encoding: .utf8) == "# 매칭\n\n최대 매칭은 간선 집합이다\n- 질문\n")
        #expect(ctx.changes.map(\.path) == [ctx.relative(url)])
        #expect(ctx.changes.allSatisfy { $0.touchesNotes })
        try run(NoteEdit(course: Self.graphTheory, note: path, append: "\n다음 줄\n"))
        #expect(try String(contentsOf: url, encoding: .utf8) == "# 매칭\n\n최대 매칭은 간선 집합이다\n- 질문\n\n다음 줄\n")
    }

    /// Nothing is written when any replacement fails, and a missing `old` reads as a change made elsewhere.
    @Test func aNoteEditRefusesAnOldThatIsMissingOrNotUnique() throws {
        let store = try ActionContext(gist: gist, device: device).store(Self.graphTheory)
        let path = "Notes/09-08(화) 매칭.md"
        let url = store.fileURL(path)
        try "a b a\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: ActionError.conflict("2번째 바꿀 원문 'c'이(가) 노트에 없습니다. 노트가 바뀌었을 수 있으니 다시 읽고 고치세요: \(path)")) {
            try run(NoteEdit(course: Self.graphTheory, note: path, replacements: [.init(old: "b", new: "B"), .init(old: "c", new: "C")]))
        }
        #expect(throws: ActionError.rule("1번째 바꿀 원문 'a'이(가) 노트에 2번 나옵니다. 앞뒤 글을 더 넣어 한 곳만 가리키세요")) {
            try run(NoteEdit(course: Self.graphTheory, note: path, replacements: [.init(old: "a", new: "A")]))
        }
        #expect(throws: ActionError.rule("1번째 바꿀 원문이 비어 있습니다")) {
            try run(NoteEdit(course: Self.graphTheory, note: path, replacements: [.init(old: "", new: "A")]))
        }
        #expect(throws: ActionError.rule("바꿀 원문이나 끝에 붙일 글을 하나 이상 주세요")) {
            try run(NoteEdit(course: Self.graphTheory, note: path, append: ""))
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "a b a\n")
    }

    @Test func everyActionHasItsOwnCommand() {
        let commands = Actions.all.map { $0.command }
        #expect(Set(commands).count == commands.count)
    }
}
