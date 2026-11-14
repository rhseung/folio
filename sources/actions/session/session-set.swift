import FolioDomain
import FolioStorage
import Foundation

@Action(
    "session set", "회차의 일시, 온라인 링크, 종류(강의, 휴강, 보강), 복습 여부, 복습 노트 상태 바꾸기. 준 것만 바뀐다",
    done: "회차 '{session}'을(를) 바꿨습니다",
    examples: [
        "folio session set EC4207/10-26 --kind cancelled", "folio session set EC4207/10-28 --kind makeup --dry-run",
        "folio session set EC4207/10-26 --review-unfinished false --dry-run",
        #"folio session set EC4207/10-26 --link https://zoom.us/j/123 --dry-run"#,
        #"folio session set EC4207/10-26 --date "2026-10-29 19:00" --end "2026-10-29 20:15" --dry-run"#,
    ],
    phrases: [
        "수업 없", "수업 안 함", "휴강", "수업 취소", "보강으로", "보강 표시", "이 수업 복습 끄기", "복습 노트 다 씀",
        "줌 링크", "수업 링크", "수업 시간 변경", "보강 시간",
    ])
public struct SessionSet {
    @Arg var course: Course.ID
    /// 회차
    @Arg var session: Session.ID
    /// 일시. 회차를 가리키는 날짜(11-03)도 따라 바뀐다
    var date: Patch<Date>
    /// 끝 일시. 수업 시간표 칸과 다를 때만 저장된다
    var end: Patch<Date?>
    /// 온라인 수업 링크(Zoom 등)
    var link: Patch<String?>
    /// 종류. lecture(강의), cancelled(휴강), makeup(보강). 휴강이면 그 회차의 출결을 지운다
    var kind: Patch<Session.Kind>
    /// 복습에서 뺄지
    var skipsReview: Patch<Bool>
    /// 복습 노트를 마저 써야 하는지
    var reviewUnfinished: Patch<Bool>

    public func run(_ ctx: ActionContext) throws {
        let start = try date.value == nil ? nil : ctx.semester(of: ctx.file(course).course)?.start
        try ctx.edit(course) { f in
            _ = try index(session, in: f.sessions, .valueSession)
            try f.set(
                session: session, date: date, end: end, link: link, kind: kind, skipsReview: skipsReview,
                reviewUnfinished: reviewUnfinished,
                termStart: start, calendar: ctx.calendar)
        }
    }
}
