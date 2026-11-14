import FolioDomain
import FolioStorage
import Foundation

@Action(
    "lms seen", "처음 본 LMS 강의실을 기록하고 지금 있는 항목을 제안함에서 숨기기",
    discussion: """
        강의실을 처음 볼 때 그 강의실에 이미 있는 파일과 공지를 --items로 넘겨, 그 뒤에 올라온 것만 제안한다.
        강의실을 과목에 잇지 않는다. 제안은 받을 때마다 과목을 고른다.
        """,
    done: "LMS 강의실 {classrooms}을(를) 기록했습니다",
    examples: ["folio lms seen 27967 28011 --items file:139109 --items notice:23464"],
    phrases: ["LMS 강의실 기록", "LMS 새 강의실"])
public struct LMSSeen {
    /// LMS 강의실 번호(course/view.php?id=)
    @Arg var classrooms: [Int]
    /// 제안함에서 숨길 항목. file:139109, notice:23464 꼴
    var items: [String] = []

    public func run(_ ctx: ActionContext) throws {
        guard !classrooms.isEmpty else { throw ActionError.input(String(localized: .errorLmsNoClassrooms)) }
        let keys = try items.map { text in
            guard let key = LMSKey(text) else { throw ActionError.input(String(localized: .errorLmsKey(text))) }
            return key
        }
        try ctx.editSettings { s in
            s.lms.know(classrooms)
            s.lms.mark(keys, handled: true)
        }
    }
}
