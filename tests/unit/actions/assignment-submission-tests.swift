import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct AssignmentSubmissionTests {
    let course = ActionTests.graphTheory
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore
    let assignment = UUID()

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
        try run(AssignmentAdd(id: assignment, course: course, title: "HW 9", due: now - 86_400))
    }

    func run(_ action: some Action, at date: Date? = nil) throws {
        try action.run(ActionContext(gist: gist, device: device, now: date ?? now))
    }

    func saved() throws -> Assignment {
        try #require(try ActionContext(gist: gist, device: device).file(course).assignments.first { $0.id == assignment })
    }

    @Test func submittingRecordsTheTimeAndLMSCanGiveItsOwn() throws {
        try run(AssignmentStatusSet(course: course, assignment: assignment, status: .submitted), at: now + 60)
        #expect(try saved().submittedAt == now + 60)
        let lms = now - 3_600
        try run(AssignmentStatusSet(course: course, assignment: assignment, status: .submitted, submittedAt: lms), at: now + 120)
        #expect(try saved().submittedAt == lms)
    }

    @Test func missingClearsTheTimeAndTakesNoTime() throws {
        try run(AssignmentStatusSet(course: course, assignment: assignment, status: .submitted))
        try run(AssignmentStatusSet(course: course, assignment: assignment, status: .missed))
        #expect(try saved().submittedAt == nil && saved().status == .missed)
        #expect(throws: ActionError.self) {
            try run(AssignmentStatusSet(course: course, assignment: assignment, status: .todo, submittedAt: now))
        }
    }

    @Test func savingKeepsTheTimeUnlessGivenAndRefusesItOnAnOpenAssignment() throws {
        try run(AssignmentSave(course: course, assignment: assignment, status: .set(.submitted)), at: now + 60)
        #expect(try saved().submittedAt == now + 60)
        try run(AssignmentSave(course: course, assignment: assignment, submittedAt: .set(now - 60)))
        #expect(try saved().submittedAt == now - 60)
        try run(AssignmentSave(course: course, assignment: assignment, lateRule: .set(LateRule(percentPerDay: 20, days: 2))))
        #expect(try saved().lateRule == LateRule(percentPerDay: 20, days: 2))
        #expect(throws: (any Error).self) {
            try run(AssignmentSave(course: course, assignment: assignment, status: .set(.todo), submittedAt: .set(now)))
        }
        #expect(throws: (any Error).self) {
            try run(AssignmentSave(course: course, assignment: assignment, lateRule: .set(LateRule(percentPerDay: 120))))
        }
    }

    @Test func theCourseRuleKeepsTheWrittenPolicy() throws {
        try run(PolicySet(course: course, latePolicy: .set("하루 10% 감점")))
        try run(PolicySet(course: course, lateRule: .set(LateRule(percentPerDay: 10, days: 3))))
        let policy = try ActionContext(gist: gist, device: device).file(course).policy
        #expect(policy.latePolicy == "하루 10% 감점" && policy.lateRule == LateRule(percentPerDay: 10, days: 3))
    }
}
