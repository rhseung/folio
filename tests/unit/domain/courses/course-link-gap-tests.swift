import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

struct CourseLinkGapTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_793_149_200)
    let day: TimeInterval = 86_400
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }

    // 모든 종류의 빈자리가 하나씩 있는 과목이다.
    func course() -> CourseFile {
        var f = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        f.materials = ["Lectures/05_Matchings.pdf", "Lectures/06_Flows.pdf"].map {
            Material(device: device, at: now, path: $0, role: .lecture, status: .classified)
        }
        var matching = Unit(device: device, at: now, title: "매칭", order: 1)
        matching.lecturePages = [UnitPages(materialId: f.materials[0].id, firstPage: 1, lastPage: 20)]
        f.units = [matching, Unit(device: device, at: now, title: "흐름", order: 2)]
        f.sessions = (0..<3).map { Session(device: device, at: now, week: $0 + 1, date: now - Double(3 - $0) * day) }
        f.sessions[2].isCancelled = true
        // 흐름 렉처는 진도 쪽이 있는데 단원 쪽 구간이 없다.
        f.linkMaterial(f.materials[1].id, session: f.sessions[0].id, firstPage: 1, lastPage: 5)
        f.exams = [
            Exam(device: device, at: now, title: "퀴즈"), Exam(device: device, at: now, title: "중간고사", start: now + 7 * day),
        ]
        let notes: [(String, NoteKind)] = [
            ("Notes/매칭.md", .unit), ("Notes/정리.md", .examSummary), ("Notes/러프.md", .rough), ("Notes/오리엔테이션.md", .free),
            ("Notes/휴강.md", .rough),
        ]
        f.notes = notes.map { NoteEntry(id: UUID(), device: device, at: now, path: $0.0, meta: NoteMeta(kind: $0.1)) }
        f.sessions[2].roughNoteId = f.notes[4].id
        return f
    }

    func gaps(_ f: CourseFile) -> [CourseLinkGap] { f.linkGaps(now: now, today: LocalDate(now, in: calendar), calendar: calendar) }

    @Test func everyKindOfGapIsFound() {
        let f = course()
        #expect(
            gaps(f) == [
                .unsplitLecture(material: f.materials[1].id), .examScopeUnknown(exam: f.exams[1].id),
                .examWithoutDate(exam: f.exams[0].id), .looseNote(note: f.notes[2].id), .looseNote(note: f.notes[0].id),
                .looseNote(note: f.notes[1].id), .cancelledSessionNote(session: f.sessions[2].id, note: f.notes[4].id),
            ])
        #expect(gaps(f).filter(\.isDangling) == [.cancelledSessionNote(session: f.sessions[2].id, note: f.notes[4].id)])
        #expect(gaps(f).allSatisfy { !f.describe($0, calendar: calendar).isEmpty })
    }

    @Test func aFreeNoteOrAFinishedExamIsNotAGap() {
        var f = course()
        f.exams[1].start = now - 10 * day
        let found = gaps(f)
        #expect(!found.contains(.looseNote(note: f.notes[3].id)))
        #expect(!found.contains(.examScopeUnknown(exam: f.exams[1].id)))
    }

    @Test func anExamBeforeAnyClassIsNotAGapYet() {
        var f = course()
        f.sessions = f.sessions.map { s in
            var s = s
            s.date = now + 3 * day
            return s
        }
        #expect(!gaps(f).contains(.examScopeUnknown(exam: f.exams[1].id)))
    }

    // 빈자리를 메우는 길은 화면마다 다르지만, 어느 순서로 메우든 다 메우면 목록이 빈다.
    @Test func fillingEveryGapEmptiesTheList() async {
        await propertyCheck(input: Gen.int(in: 0...1000)) { seed in
            var f = course()
            var order = gaps(f)
            var rng = SplitMix(seed: UInt64(seed))
            order.shuffle(using: &rng)
            for gap in order { fill(gap, in: &f) }
            #expect(gaps(f).isEmpty)
        }
    }

    func fill(_ gap: CourseLinkGap, in f: inout CourseFile) {
        switch gap {
        case .unsplitLecture(let m):
            f.units[1].lecturePages.append(UnitPages(materialId: m, firstPage: 1, lastPage: 10))
        case .examWithoutDate(let id):
            guard let e = f.exams.firstIndex(where: { $0.id == id }) else { return }
            f.exams[e].start = now + 3 * day
            f.addScope([f.units[0].id], exam: id)
        case .examScopeUnknown(let id):
            f.addScope([f.units[0].id], exam: id)
        case .looseNote(let id):
            guard let n = f.notes.firstIndex(where: { $0.id == id }) else { return }
            switch f.notes[n].kind {
            case .unit: f.notes[n].unitIds = [f.units[0].id]
            case .examSummary: f.notes[n].examId = f.exams[1].id
            default: f.sessions[1].roughNoteId = id
            }
        case .cancelledSessionNote(let s, _):
            // 뗀 노트는 걸 데 없는 노트가 되므로 다른 수업에 옮겨 단다.
            guard let i = f.sessions.firstIndex(where: { $0.id == s }) else { return }
            f.sessions[0].roughNoteId = f.sessions[i].roughNoteId
            f.sessions[i].roughNoteId = nil
        }
    }
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
