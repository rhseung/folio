import FolioDomain
import FolioStorage
import Foundation

@Action(
    "lms submitted", "LMS에서 낸 받은 과제를 Folio에서 제출함으로 바꾸기. 앱의 동기화가 승인 없이 부른다",
    discussion: """
        항목 파일은 [{"course":"<과목 ID>","assignment":"<과제 ID>","lms":139950,"at":"2026-11-03T14:20:00Z"}] 꼴이다.
        at은 LMS의 마지막 제출 시각이고, 빼면 바꾼 시각을 낸 시각으로 적는다. 바꾼 과제는 submitted:<LMS 과제> 키로 남겨, 다시 할 일로 돌려도 또 바꾸지 않는다.
        """,
    done: "LMS에서 낸 과제를 제출함으로 바꿨습니다",
    phrases: ["LMS 제출 반영", "LMS에서 낸 과제"])
public struct LMSSubmitted {
    /// 바꿀 과제
    @FromFile("items.json") var items: [LMSSubmission]

    public func run(_ ctx: ActionContext) throws {
        guard !items.isEmpty else { throw ActionError.input(String(localized: .errorLmsNoKeys)) }
        // 쓰기 전에 모든 과제를 찾아, 하나가 없으면 아무것도 바꾸지 않는다.
        for item in items {
            guard try ctx.file(item.course).assignments.contains(where: { $0.id == item.assignment }) else {
                throw ActionError.notFound(String(localized: .errorLmsAssignmentMissing("submitted:\(item.lms)")))
            }
        }
        for item in items {
            try AssignmentStatusSet(course: item.course, assignment: item.assignment, status: .submitted, submittedAt: item.at).run(ctx)
        }
        try ctx.editSettings { s in s.lms.mark(items.map(\.key), handled: true) }
    }
}
