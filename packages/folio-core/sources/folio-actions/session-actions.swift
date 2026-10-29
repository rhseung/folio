import FolioDomain
import FolioStorage
import Foundation

func index<E: Identifiable>(_ id: E.ID, in items: [E], _ what: LocalizedStringResource) throws -> Int {
    guard let i = items.firstIndex(where: { $0.id == id }) else { throw ActionError.notFound(String(localized: .errorNotFoundItem(String(localized: what)))) }
    return i
}

@Action("session add", "회차 추가. 주차와 순번은 학기 시작일에서 정한다", effect: .creates, done: "회차를 추가했습니다",
        examples: [#"folio session add EC4207 --date "2026-10-28 10:30""#, "folio session add EC4207 --date 2026-10-30 --cancelled --dry-run"],
        phrases: ["보충", "보충수업", "잡혔", "수업 추가", "보강", "추가 수업", "회차 만들기"])
public struct SessionAdd {
    @New var id: Session.ID
    /// 과목
    @Arg var course: Course.ID
    /// 일시. 2026-10-28 또는 "2026-10-28 10:30"
    var date: Date
    /// 수업이 없던 날의 휴강으로
    var cancelled = false

    public func run(_ ctx: ActionContext) throws {
        let start = try ctx.semester(of: ctx.file(course).course)?.start
        try ctx.edit(course) { f in
            guard !f.sessions.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenSession("\(id)"))) }
            var s = SessionPlanner.session(at: date, sessions: f.sessions, termStart: start, calendar: ctx.calendar,
                                           device: ctx.device, now: ctx.now)
            s.id = id
            s.isCancelled = cancelled
            f.sessions.append(s)
        }
        ctx.made(id)
    }
}

/// Only sessions nothing points at: a note, recording or other link left pointing at nothing is worse than a stray
/// session. An unreadable note folder might point at any of them, so none goes then.
@Action("session rm", "아무것도 연결되지 않은 회차 지우기", effect: .removes, confirm: "회차 {sessions}을(를) 지웁니다.",
        done: "회차 {sessions}을(를) 지웠습니다", cli: .manual)
public struct SessionRemove {
    @Arg var course: Course.ID
    /// 회차
    @Arg var sessions: [Session.ID]

    public func run(_ ctx: ActionContext) throws {
        let noted = Set(try ctx.store(course).notes().compactMap(\.meta.sessionId))
        try ctx.edit(course) { f in
            for id in sessions {
                let s = f.sessions[try index(id, in: f.sessions, .valueSession)]
                guard f.isUnlinked(s, notedSessions: noted) else {
                    throw ActionError.rule(String(localized: .errorSessionLinked(f.name(of: s))))
                }
            }
            f.sessions.removeAll { sessions.contains($0.id) }
        }
    }
}

@Action("session set", "회차의 휴강, 복습 여부, 복습 노트 상태 바꾸기", done: "회차 '{session}'을(를) 바꿨습니다",
        examples: ["folio session set EC4207/9주차-1 --cancelled true", "folio session set EC4207/9주차-1 --review-unfinished false --dry-run"],
        phrases: ["수업 없", "수업 안 함", "휴강", "수업 취소", "이 수업 복습 끄기", "복습 노트 다 씀"])
public struct SessionSet {
    @Arg var course: Course.ID
    /// 회차
    @Arg var session: Session.ID
    /// 휴강인지. 휴강이면 그 회차의 출결을 지운다
    var cancelled: Patch<Bool>
    /// 복습에서 뺄지
    var skipsReview: Patch<Bool>
    /// 복습 노트를 마저 써야 하는지
    var reviewUnfinished: Patch<Bool>

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.sessions, session) { s in
                cancelled.apply(&s.isCancelled)
                skipsReview.apply(&s.skipsReview)
                reviewUnfinished.apply(&s.reviewNoteUnfinished)
            }
            // A class that didn't happen has no attendance to count.
            if cancelled.value == true { f.attendance.removeAll { $0.sessionId == session } }
        }
    }
}

/// The session's rough or review note, created from its template the first time (docs/SPEC.md "러프 노트는 처음 열 때
/// 만들어진다"). A new review note starts unfinished: making it is not writing it.
@Action("session note", "회차의 러프·복습 노트. 없으면 템플릿으로 만든다", effect: .creates, done: "회차 '{session}'의 노트",
        examples: ["folio session note EC4207/9주차-1 review"], phrases: ["수업 노트", "강의 필기", "러프 노트", "복습 노트 열기"])
public struct SessionNote {
    /// The new note's id; unused when the note already exists.
    @New var id: Note.ID
    @Arg var course: Course.ID
    /// 회차
    @Arg var session: Session.ID
    /// rough 또는 review
    @Arg var kind: NoteKind

    public func run(_ ctx: ActionContext) throws {
        guard kind == .rough || kind == .review else { throw ActionError.rule(String(localized: .errorSessionNoteKind)) }
        let file = try ctx.file(course)
        let s = file.sessions[try index(session, in: file.sessions, .valueSession)]
        if let id = kind == .rough ? s.roughNoteId : s.reviewNoteId {
            ctx.made(id)
            return
        }
        let settings = try ctx.settings()
        let title = kind == .rough ? file.name(of: s) : "\(file.name(of: s)) 정리"
        let body = NoteTemplate.body(for: kind, title: title, sections: settings.noteSections(for: kind))
        let made = try ctx.createNote(course, title: title, meta: NoteMeta(id: id, kind: kind, sessionId: s.id, unitIds: s.unitIds,
                                                                           math: settings.newNoteMath), body: body) ?? id
        try ctx.edit(course) { f in
            let i = try index(session, in: f.sessions, .valueSession)
            if kind == .rough {
                f.sessions[i].roughNoteId = made
            } else {
                f.sessions[i].reviewNoteId = made
                f.sessions[i].reviewNoteUnfinished = true
            }
        }
        ctx.made(made)
    }
}

/// Present is the default, so it is stored as no entry.
@Action("attendance set", "회차의 출결 정하기. 출석이 기본값이다", done: "회차 '{session}'의 출결을 {state}(으)로 정했습니다",
        examples: ["folio attendance set EC4207/9주차-1 absent"],
        phrases: ["빠졌", "못 갔", "안 갔", "결석", "지각", "공결", "출석 체크", "수업 빠짐", "못 갔어"])
public struct AttendanceSet {
    @Arg var course: Course.ID
    /// 회차
    @Arg var session: Session.ID
    /// 출결
    @Arg var state: AttendanceState

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(session, in: f.sessions, .valueSession)
            f.attendance.removeAll { $0.sessionId == session }
            if state != .present { f.attendance.append(Attendance(device: ctx.device, at: ctx.now, sessionId: session, state: state)) }
        }
    }
}

// MARK: Units

@Action("unit add", "단원 추가. 형제 단원 맨 뒤에 놓인다", effect: .creates, done: "단원 '{title}'을(를) 추가했습니다",
        examples: ["folio unit add EC4207 트리", #"folio unit add EC4207 "스패닝 트리" --parent 트리 --dry-run"#],
        phrases: ["단원 추가", "챕터 추가", "새 단원"])
public struct UnitAdd {
    @New var id: FolioDomain.Unit.ID
    /// 과목
    @Arg var course: Course.ID
    /// 단원 제목
    @Arg var title: String
    /// 상위 단원. 없으면 맨 위
    var parent: FolioDomain.Unit.ID?

    public func run(_ ctx: ActionContext) throws {
        let name = title.trimmingCharacters(in: .whitespaces)
        try ctx.edit(course) { f in
            guard !f.units.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenUnit("\(id)"))) }
            f.units.append(FolioDomain.Unit(id: id, device: ctx.device, at: ctx.now, title: name, order: UnitTree.nextOrder(under: parent, in: f.units), parentId: parent))
        }
        ctx.made(id)
    }
}

/// Session and exam links let go; children move up a level. Notes and quiz files stay.
@Action("unit rm", "단원 지우기. 하위 단원은 한 단계 올라간다. 회차와 시험 범위의 연결은 풀리고, 노트와 퀴즈 파일은 남는다", effect: .removes,
        confirm: "단원 '{unit}'을(를) 지우고 회차와 시험 범위 연결을 풉니다.", done: "단원 '{unit}'을(를) 지웠습니다",
        examples: ["folio unit rm EC4207/트리 --dry-run"], phrases: ["단원 삭제"])
public struct UnitRemove {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(unit, in: f.units, .valueUnit)
            f.removeUnit(unit)
        }
    }
}

@Action("unit set", "단원 제목 바꾸기", done: "단원 '{unit}'의 제목을 바꿨습니다",
        examples: [#"folio unit set EC4207/트리 --title "트리와 숲""#], phrases: ["단원 제목", "단원 이름 바꾸기", "챕터 이름"])
public struct UnitSet {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 새 제목
    var title: String

    public func run(_ ctx: ActionContext) throws {
        let name = title.trimmingCharacters(in: .whitespaces)
        try ctx.edit(course) { f in
            try f.update(\.units, unit) { u in
                guard u.title != name else { return }
                u.title = name
                u.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}

/// Moves a unit among its siblings (`by` -1 up, 1 down) or under another parent (nil for the top level).
@Action("unit move", "단원을 형제 사이에서 옮기거나 다른 단원 아래로 옮기기", done: "단원 '{unit}'을(를) 옮겼습니다", cli: .manual)
public struct UnitMove {
    public enum Target: Codable, Sendable, Equatable {
        case by(Int), parent(UUID?)
        // CaseIterable lets `folio actions --schema` list every case; Codable synthesis still uses these keys.
        enum CodingKeys: CodingKey, CaseIterable { case by, parent }
    }
    @Arg var course: Course.ID
    @Arg var unit: FolioDomain.Unit.ID
    var target: Target

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(unit, in: f.units, .valueUnit)
            switch target {
            // Already first or last: nothing to do, as with the app's arrow buttons.
            case .by(let offset): _ = UnitTree.move(unit, by: offset, in: &f.units)
            case .parent(let parent):
                guard UnitTree.setParent(unit, to: parent, in: &f.units) else { throw ActionError.rule(String(localized: .errorUnitCycle)) }
            }
        }
    }
}

/// Links or unlinks sessions, keeping `Unit.sessionIds` and `Session.unitIds` in step.
@Action("unit link", "단원에 회차 연결하기, --off면 풀기", done: "단원 '{unit}'의 회차 연결을 바꿨습니다",
        examples: ["folio unit link EC4207/트리 9주차-1 9주차-2", "folio unit link EC4207/트리 9주차-2 --off --dry-run"],
        phrases: ["단원과 수업 연결", "이 수업에서 배운 단원"])
public struct UnitLink {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 회차. 예: 9주차-1
    @Arg var sessions: [Session.ID]
    /// 연결 풀기
    @Off("off") var linked = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            let u = try index(unit, in: f.units, .valueUnit)
            for session in sessions {
                _ = try index(session, in: f.sessions, .valueSession)
                if f.units[u].sessionIds.contains(session) != linked { f.toggle(session: session, unit: unit) }
            }
        }
    }
}

/// Puts a unit, with the units under it, into an exam's scope or takes it out.
@Action("exam scope", "시험 범위에 단원 넣기, --off면 빼기", done: "시험 '{exam}'의 범위를 바꿨습니다", cli: .manual)
public struct ExamScope {
    @Arg var course: Course.ID
    @Arg var exam: Exam.ID
    /// 단원
    var unit: FolioDomain.Unit.ID
    /// 범위에서 빼기
    @Off("off") var included = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            let e = try index(exam, in: f.exams, .valueExam)
            _ = try index(unit, in: f.units, .valueUnit)
            if f.exams[e].scopeUnitIds.contains(unit) != included { f.toggle(exam: exam, unit: unit) }
        }
    }
}
