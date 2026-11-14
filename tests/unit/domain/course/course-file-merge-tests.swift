import Foundation
import Testing

@testable import FolioDomain

struct CourseFileMergeTests {
    let early = Date(timeIntervalSince1970: 1_790_000_000)
    let late = Date(timeIntervalSince1970: 1_790_000_600)
    let device = UUID()
    let id = UUID()

    func course(at date: Date) -> CourseFile {
        CourseFile(course: Course(id: id, device: device, at: date, title: "그래프 이론"))
    }

    func exam(_ id: UUID, _ title: String, at date: Date) -> Exam { Exam(id: id, device: device, at: date, title: title) }

    @Test func itemsUnionByIDAndTheLaterEditWins() {
        let shared = UUID(), mine = UUID(), theirs = UUID()
        var a = course(at: early)
        a.exams = [exam(shared, "중간", at: early), exam(mine, "퀴즈 1", at: early)]
        var b = course(at: late)
        b.exams = [exam(shared, "중간고사", at: late), exam(theirs, "퀴즈 2", at: late)]
        let merged = a.merged(with: b)
        #expect(merged.exams.map(\.id) == [shared, theirs, mine])
        #expect(merged.exams.first?.title == "중간고사")
        #expect(merged.course == b.course)
        #expect(b.merged(with: a) == merged)
    }

    @Test func appliedProposalsAreCollected() {
        let p = UUID(), q = UUID()
        var a = course(at: early)
        a.recordApplied(p)
        var b = course(at: late)
        b.recordApplied(q)
        b.recordApplied(p)
        #expect(Set(a.merged(with: b).appliedProposals ?? []) == [p, q])
        #expect(course(at: early).merged(with: course(at: late)).appliedProposals == nil)
    }

    @Test func recordingTwiceKeepsOneID() {
        var a = course(at: early)
        let p = UUID()
        a.recordApplied(p)
        a.recordApplied(p)
        #expect(a.appliedProposals == [p])
        #expect(a.hasApplied(p))
    }
}
