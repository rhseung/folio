import FolioDomain
import Foundation
import Testing

@testable import FolioStorage

struct ExamKindMigrationTests {
    func exam(_ kind: String, title: String) -> JSONValue {
        .object(["kind": .string(kind), "title": .string(title), "futureExamField": .string("keep me")])
    }

    @Test func eachExamKeepsTheFolderItsKindNamed() throws {
        var raw: JSONValue = .object([
            "exams": .array([
                exam("midterm", title: "중간고사"),
                exam("quiz", title: ""),
                exam("quiz", title: "쪽지시험"),
                exam("final", title: "Quiz7"),
                exam("other", title: "구술"),
                exam("other", title: ""),
                exam("other", title: "Midterm 대비"),
                exam("other", title: "구술"),
            ])
        ])
        try CourseFile.dropExamKind(&raw)
        guard case .array(let exams)? = raw["exams"] else { Issue.record("no exams"); return }
        #expect(exams.allSatisfy { $0["kind"] == nil && $0["futureExamField"] == .string("keep me") })

        #expect(
            exams.map { $0["folder"] } == ["Midterm", "Quiz1", "Quiz2", "Quiz7", "구술", "Exam", "Midterm 대비", "구술 2"].map(JSONValue.string))

        #expect(exams.map { $0["title"] } == ["중간고사", "Quiz1", "쪽지시험", "Quiz7", "구술", "Exam", "Midterm 대비", "구술"].map(JSONValue.string))
    }
}
