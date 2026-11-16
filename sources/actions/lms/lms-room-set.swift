import FolioDomain
import FolioStorage
import Foundation

@Action(
    "lms room", "LMS 강의실에서 받을 과목을 기억하기. --none이면 과목 없음, --forget이면 기억 지우기",
    discussion: """
        강의실을 과목에 미리 잇지 않는다. 받을 때 고른 과목을 강의실마다 기억해 다음 받기에서 미리 고르고, 이 명령은 그 기억을 바꾼다.
        과목 없음은 소방 교육처럼 과목이 아닌 강의실이다.
        """,
    done: "LMS 강의실 {classroom}의 과목을 바꿨습니다",
    examples: ["folio lms room 27967 EC4207", "folio lms room 28011 --none", "folio lms room 27967 --forget"],
    phrases: ["LMS 강의실 과목", "강의실 과목 기억", "강의실 과목 바꾸기"])
public struct LMSRoomSet {
    /// LMS 강의실 번호(course/view.php?id=)
    @Arg var classroom: Int
    /// 받을 과목
    @Arg var course: Course.ID?
    /// 과목 없음으로 기억하기
    var none = false
    /// 기억 지우기
    var forget = false

    public func run(_ ctx: ActionContext) throws {
        guard [course != nil, none, forget].filter({ $0 }).count == 1 else {
            throw ActionError.input(String(localized: .errorLmsRoomChoice))
        }
        if let course { _ = try ctx.file(course) }
        let room = forget ? nil : LMSRoom(course: course)
        try ctx.editSettings { $0.lms.remember(room, for: classroom) }
    }
}
