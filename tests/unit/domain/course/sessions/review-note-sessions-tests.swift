import FolioDomain
import Foundation
import PropertyBased
import Testing

struct ReviewNoteSessionsTests {
    let device = UUID()
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    // 9주차부터 일주일 간격으로 하루 차이의 수업이 두 개씩 있어서, index 순서가 날짜 순서와 같다.
    func sessions(_ count: Int) -> [Session] {
        (0..<count).map { Session(device: device, at: start, week: 9 + $0 / 2, date: start.addingTimeInterval(Double($0) * 86_400)) }
    }

    func file(_ sessions: [Session], notes: [(UUID, NoteKind)] = []) -> CourseFile {
        var file = CourseFile(course: Course(device: device, at: start, title: "컴퓨터네트워킹"), sessions: sessions)
        file.notes = notes.map {
            NoteEntry(id: $0.0, device: device, at: start, path: "Notes/\($0.0).md", meta: NoteMeta(id: $0.0, kind: $0.1))
        }
        return file
    }

    func violations(_ file: CourseFile) -> Set<String> { Set(CourseFile.model.violations(in: file).map(\.rule.name)) }

    @Test func aReviewNoteCoversSeveralSessionsInDateOrder() {
        let s = sessions(4), note = UUID()
        var f = file(s, notes: [(note, .review)])
        f.linkNote(note, to: s[2].id, as: .review)
        f.linkNote(note, to: s[0].id, as: .review)
        #expect(f.sessions.map(\.reviewNoteId) == [note, nil, note, nil])
        #expect(f.sessions(pointingAt: note).map(\.id) == [s[0].id, s[2].id])
        #expect(
            f.sessionSpan(of: note, calendar: calendar) == "\(f.day(of: s[0], calendar: calendar)) – \(f.day(of: s[2], calendar: calendar))"
        )
        #expect(f.meta(of: f.notes[0]).sessionIds == [s[0].id, s[2].id] && f.meta(of: f.notes[0]).sessionId == s[0].id)
        #expect(violations(f).isDisjoint(with: ["NoteEntry.session", "Session.noteKind"]))

        f.unlinkNote(note, from: s[0].id)
        #expect(
            f.sessions(pointingAt: note).map(\.id) == [s[2].id]
                && f.sessionSpan(of: note, calendar: calendar) == f.day(of: s[2], calendar: calendar))
        f.linkNote(note, to: s[3].id, as: .review)
        f.forgetNote(note)
        #expect(f.sessions(pointingAt: note).isEmpty && f.sessionSpan(of: note, calendar: calendar) == nil)
        #expect(f.sessions(pointingAt: nil).isEmpty)
    }

    @Test func aRoughNoteStaysWithOneSession() {
        let s = sessions(2), note = UUID()
        var f = file(s, notes: [(note, .rough)])
        f.linkNote(note, to: s[0].id, as: .rough)
        f.linkNote(note, to: s[1].id, as: .rough)
        #expect(f.sessions.map(\.roughNoteId) == [nil, note])
        f.sessions[0].roughNoteId = note
        #expect(violations(f).contains("NoteEntry.session"))
    }

    @Test func becomingAReviewNoteLeavesTheRoughSlot() {
        let s = sessions(2), note = UUID()
        var f = file(s, notes: [(note, .review)])
        f.linkNote(note, to: s[0].id, as: .rough)
        f.linkNote(note, to: s[1].id, as: .review)
        #expect(f.sessions.map(\.roughNoteId) == [nil, nil] && f.sessions.map(\.reviewNoteId) == [nil, note])
        f.linkNote(note, to: s[0].id, as: .review)
        f.linkNote(note, to: nil, as: .review)
        #expect(f.sessions(pointingAt: note).isEmpty)
    }

    @Test func theClassesOfANoteFinishTogether() {
        let s = sessions(3), note = UUID()
        let now = start.addingTimeInterval(10 * 86_400)
        var f = file(s, notes: [(note, .review)])

        #expect(s.allSatisfy { f.needsReviewNote($0, at: now) })

        f.linkNote(note, to: s[0].id, as: .review)
        f.sessions[0].reviewNoteUnfinished = true
        f.linkNote(note, to: s[1].id, as: .review)
        #expect(f.sessions[1].reviewNoteUnfinished && f.isReviewNoteUnfinished(note))
        #expect(f.sessions.map { f.needsReviewNote($0, at: now) } == [true, true, true])
        f.setReviewNoteUnfinished(note, false)
        #expect(f.sessions.map { f.needsReviewNote($0, at: now) } == [false, false, true])

        f.linkNote(note, to: s[1].id, as: .review)
        #expect(!f.sessions[1].reviewNoteUnfinished)
    }

    @Test func theSchedulerSeesTheSharedNoteOnEachClass() {
        let s = sessions(2), note = UUID()
        let now = start.addingTimeInterval(10 * 86_400)
        var f = file(s, notes: [(note, .review)])
        var first = FolioDomain.Unit(device: device, at: start, title: "rdt", order: 0)
        var second = FolioDomain.Unit(device: device, at: start, title: "Go-Back-N", order: 1)
        first.sessionIds = [s[0].id]
        second.sessionIds = [s[1].id]
        f.units = [first, second]
        f.sessions[0].unitIds = [first.id]
        f.sessions[1].unitIds = [second.id]
        func needs() -> [Bool] {
            UnitReviewInput.all(for: f, reviews: [], settings: Settings(), calendar: calendar, now: now).map(\.needsReviewNote)
        }

        #expect(needs() == [true, true])
        f.linkNote(note, to: s[0].id, as: .review)
        f.linkNote(note, to: s[1].id, as: .review)
        #expect(needs() == [false, false])
        #expect(f.meta(of: f.notes[0]).unitIds == [first.id, second.id])
    }

    // MARK: Properties

    static let picks = Gen.int(in: 0...1).array(of: 1...8)
    static let order = Gen.int(in: 0...1_000).array(of: 8...8)

    @Test func linkingInAnyOrderReadsBackInDateOrder() async {
        await propertyCheck(input: Self.picks, Self.order) { picks, order in
            let s = sessions(picks.count), note = UUID(), other = UUID()
            var f = file(s.indices.sorted { order[$0] < order[$1] }.map { s[$0] }, notes: [(note, .review), (other, .review)])
            let chosen = s.indices.filter { picks[$0] == 1 }
            for i in chosen.sorted(by: { order[$0] > order[$1] }) { f.linkNote(note, to: s[i].id, as: .review) }
            #expect(f.sessions(pointingAt: note).map(\.id) == chosen.map { s[$0].id })
            #expect(violations(f).isDisjoint(with: ["NoteEntry.session", "Session.noteKind"]))

            if let first = chosen.first, let last = chosen.last {
                let span = f.sessionSpan(of: note, calendar: calendar)
                let day = { (i: Int) in f.day(of: s[i], calendar: calendar) }
                #expect(first == last ? span == day(first) : span == "\(day(first)) – \(day(last))")
            }
            if let dropped = chosen.min(by: { order[$0] < order[$1] }) {
                f.unlinkNote(note, from: s[dropped].id)
                #expect(f.sessions(pointingAt: note).map(\.id) == chosen.filter { $0 != dropped }.map { s[$0].id })
            }

            let free = s.indices.filter { picks[$0] == 0 }
            for i in free { f.linkNote(other, to: s[i].id, as: .review) }
            f.forgetNote(note)
            #expect(f.sessions(pointingAt: note).isEmpty)
            #expect(f.sessions(pointingAt: other).map(\.id) == free.map { s[$0].id })
        }
    }
}
