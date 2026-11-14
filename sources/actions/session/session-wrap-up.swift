import FolioDomain
import FolioStorage
import Foundation

@Action(
    "session wrap-up", "회차 편집과 수업 정리: 렉처 진도, 단원, 출결, 복습, 일시, 종류, 온라인 링크를 한 번에 적는다. 끝난 수업이면 정리했다고 표시한다",
    discussion: "렉처 파일은 <자료>:<시작>-<끝>으로 쓴다. 주지 않은 것은 그대로 둔다. 끝났거나 녹음을 마친 수업(휴강 아님)이면 정리했다고 표시해 오늘 화면의 수업 정리에서 뺀다.",
    done: "회차 '{session}'을(를) 저장했습니다",
    examples: [
        "folio session wrap-up EC4207/10-26 05_Matchings.pdf:7-11 --unit 매칭",
        "folio session wrap-up EC4207/10-26 --attendance late --dry-run",
        "folio session wrap-up EC4207/10-26 --review-unfinished false --kind makeup --dry-run",
    ],
    phrases: ["수업 정리", "수업 끝", "오늘 수업 정리", "수업 마무리", "회차 편집"])
public struct SessionWrapUp {
    /// 과목
    @Arg var course: Course.ID
    /// 회차
    @Arg var session: Session.ID
    /// 렉처 파일마다 이번 수업이 다룬 쪽. 적지 않은 파일의 연결은 그대로 둔다
    @Arg @Parsed("material:pages", "05_Matchings.pdf:3-12") var ranges: [SessionMaterial] = []
    /// 회차에서 뗄 자료. 그 자료의 진도도 함께 지운다
    @CLIName("unlink") var unlinked: [Material.ID] = []
    /// 회차의 단원. 주면 이것으로 바뀐다
    @CLIName("unit") var units: Patch<[FolioDomain.Unit.ID]>
    /// 출결
    var attendance: Patch<AttendanceState>
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
    /// 녹음을 막 멈춘 수업. 앱이 녹음을 멈출 때 연 시트가 준다. 녹음은 압축이 끝나야 course.json에 기록되고 압축이 실패하면 끝내 기록되지 않으므로, 이 값 없이는 끝 시각 전에 저장한 정리가 정리로 남지 않는다
    @Hidden var recorded = false

    public func run(_ ctx: ActionContext) throws {
        let start = try date.value == nil ? nil : ctx.semester(of: ctx.file(course).course)?.start
        let classMinutes = try ctx.settings().classMinutes
        try ctx.edit(course) { f in
            _ = try index(session, in: f.sessions, .valueSession)
            try f.set(
                session: session, date: date, end: end, link: link, kind: kind, skipsReview: skipsReview,
                reviewUnfinished: reviewUnfinished,
                termStart: start, calendar: ctx.calendar)

            let i = try index(session, in: f.sessions, .valueSession)
            // 범위보다 먼저 뗀다. 그래야 함께 주고 뗀 파일이 준 쪽으로 연결된다.
            for material in unlinked {
                _ = try index(material, in: f.materials, .valueMaterial)
                f.unlinkMaterial(material, session: session)
            }
            for range in ranges {
                _ = try index(range.materialId, in: f.materials, .valueMaterial)
                f.linkMaterial(range.materialId, session: session, firstPage: range.firstPage, lastPage: range.lastPage)
            }

            if case .set(let units) = units {
                for unit in units { _ = try index(unit, in: f.units, .valueUnit) }
                for unit in Set(f.sessions[i].unitIds).symmetricDifference(units) { f.toggle(session: session, unit: unit) }
            }

            // 시트는 늘 수업의 출결을 넘기므로, 이미 그 상태인 항목은 시각과 기기를 지킨다.
            let had = f.attendance.first { $0.sessionId == session }?.state ?? .present
            if case .set(let state) = attendance, had != state {
                f.attendance.removeAll { $0.sessionId == session }
                if state != .present { f.attendance.append(Attendance(device: ctx.device, at: ctx.now, sessionId: session, state: state)) }
            }

            let s = f.sessions[i]
            if s.isCancelled { f.attendance.removeAll { $0.sessionId == session } }
            if f.savingWrapsUp(s, recorded: recorded, at: ctx.now, classMinutes: classMinutes, calendar: ctx.calendar) {
                f.sessions[i].isWrappedUp = true
            }
        }
    }
}
