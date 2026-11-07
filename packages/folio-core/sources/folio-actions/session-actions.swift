import FolioDomain
import FolioStorage
import Foundation

func index<E: Identifiable>(_ id: E.ID, in items: [E], _ what: LocalizedStringResource) throws -> Int {
    guard let i = items.firstIndex(where: { $0.id == id }) else { throw ActionError.notFound(String(localized: .errorNotFoundItem(String(localized: what)))) }
    return i
}

@Action("session add", "회차 추가. 주차는 학기 시작일에서 정한다", effect: .creates, done: "회차를 추가했습니다",
        examples: [#"folio session add EC4207 --date "2026-10-28 10:30""#, "folio session add EC4207 --date 2026-10-30 --cancelled --dry-run",
                   #"folio session add EC4207 --date "2026-11-04 21:00" --end "2026-11-04 22:15" --link https://zoom.us/j/123 --dry-run"#,
                   #"folio session add EC4207 --date "2026-11-11 10:30" --attendance absent --dry-run"#],
        phrases: ["보충", "보충수업", "잡혔", "수업 추가", "보강", "추가 수업", "회차 만들기", "줌 수업", "온라인 수업", "비대면 수업"])
public struct SessionAdd {
    @New var id: Session.ID
    /// 과목
    @Arg var course: Course.ID
    /// 일시. 2026-10-28 또는 "2026-10-28 10:30"
    var date: Date
    /// 끝 일시. 수업 시간표에 없는 시간일 때만 필요하다
    var end: Date?
    /// 온라인 수업 링크(Zoom 등)
    var link: String?
    /// 수업이 없던 날의 휴강으로
    var cancelled = false
    /// 출결. 결석이나 공결을 미리 알 때. 휴강과 함께 줄 수 없다
    var attendance: AttendanceState?

    public func run(_ ctx: ActionContext) throws {
        let start = try ctx.semester(of: ctx.file(course).course)?.start
        try ctx.edit(course) { f in
            guard !f.sessions.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenSession("\(id)"))) }
            var s = SessionPlanner.session(at: date, sessions: f.sessions, termStart: start, calendar: ctx.calendar,
                                           device: ctx.device, now: ctx.now)
            s.id = id
            s.isCancelled = cancelled
            s.link = OnlineLink.stored(link)
            s.setEnd(end, schedule: f.course.schedule, calendar: ctx.calendar)
            f.sessions.append(s)
            // In the same edit as the session, so a refused attendance (on a 휴강) leaves no session behind.
            if let attendance, attendance != .present {
                f.attendance.append(Attendance(device: ctx.device, at: ctx.now, sessionId: id, state: attendance))
            }
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
        let noted = Set(try ctx.notes(course).flatMap(\.meta.sessionIds))
        try ctx.edit(course) { f in
            for id in sessions {
                let s = f.sessions[try index(id, in: f.sessions, .valueSession)]
                guard f.isUnlinked(s, notedSessions: noted) else {
                    throw ActionError.rule(String(localized: .errorSessionLinked(f.title(of: s, calendar: ctx.calendar))))
                }
            }
            f.sessions.removeAll { sessions.contains($0.id) }
        }
    }
}

@Action("session set", "회차의 일시, 온라인 링크, 휴강, 복습 여부, 복습 노트 상태 바꾸기. 준 것만 바뀐다",
        done: "회차 '{session}'을(를) 바꿨습니다",
        examples: ["folio session set EC4207/10-26 --cancelled true", "folio session set EC4207/10-26 --review-unfinished false --dry-run",
                   #"folio session set EC4207/10-26 --link https://zoom.us/j/123 --dry-run"#,
                   #"folio session set EC4207/10-26 --date "2026-10-29 19:00" --end "2026-10-29 20:15" --dry-run"#],
        phrases: ["수업 없", "수업 안 함", "휴강", "수업 취소", "이 수업 복습 끄기", "복습 노트 다 씀",
                  "줌 링크", "수업 링크", "수업 시간 변경", "보강 시간"])
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
    /// 휴강인지. 휴강이면 그 회차의 출결을 지운다
    var cancelled: Patch<Bool>
    /// 복습에서 뺄지
    var skipsReview: Patch<Bool>
    /// 복습 노트를 마저 써야 하는지
    var reviewUnfinished: Patch<Bool>

    public func run(_ ctx: ActionContext) throws {
        let start = try date.value == nil ? nil : ctx.semester(of: ctx.file(course).course)?.start
        try ctx.edit(course) { f in
            _ = try index(session, in: f.sessions, .valueSession)
            if let date = date.value { f.reschedule(session, to: date, termStart: start, calendar: ctx.calendar) }
            let schedule = f.course.schedule
            try f.update(\.sessions, session) { s in
                if let end = end.value { s.setEnd(end, schedule: schedule, calendar: ctx.calendar) }
                if let link = link.value { s.link = OnlineLink.stored(link) }
                cancelled.apply(&s.isCancelled)
                skipsReview.apply(&s.skipsReview)
                reviewUnfinished.apply(&s.reviewNoteUnfinished)
            }
            // A review note covering several classes is written once, so they are marked together.
            if let unfinished = reviewUnfinished.value, let note = f.sessions.first(where: { $0.id == session })?.reviewNoteId {
                f.setReviewNoteUnfinished(note, unfinished)
            }
            // A class that didn't happen has no attendance to count.
            if cancelled.value == true { f.attendance.removeAll { $0.sessionId == session } }
        }
    }
}

/// The session's rough or review note, created from its template the first time.
/// A new review note starts unfinished: making it is not writing it.
@Action("session note", "회차의 러프 노트와 복습 노트. 없으면 템플릿으로 만든다", effect: .creates, done: "회차 '{session}'의 노트",
        examples: ["folio session note EC4207/10-26 review"], phrases: ["수업 노트", "강의 필기", "러프 노트", "복습 노트 열기"])
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
        if let id = s.note(of: kind) {
            ctx.made(id)
            return
        }
        let settings = try ctx.settings()
        let title = file.noteTitle(for: s, kind: kind, calendar: ctx.calendar)
        let body = NoteTemplate.body(for: kind, title: title, sections: settings.noteSections(for: kind))
        let made = try ctx.createNote(course, title: title, meta: NoteMeta(id: id, kind: kind, math: settings.newNoteMath), body: body)
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
        examples: ["folio attendance set EC4207/10-26 absent"],
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

/// Everything linked to the unit lets go of it; children move up a level. Notes and quiz files stay.
@Action("unit rm", "단원 지우기. 하위 단원은 한 단계 올라간다. 회차, 시험 범위, 자료, 노트, 문제의 연결은 풀리고, 노트와 퀴즈 파일은 남는다", effect: .removes,
        confirm: "단원 '{unit}'을(를) 지우고 회차, 시험 범위, 자료, 노트, 문제의 연결을 풉니다.", done: "단원 '{unit}'을(를) 지웠습니다",
        examples: ["folio unit rm EC4207/트리 --dry-run"], phrases: ["단원 삭제"])
public struct UnitRemove {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(unit, in: f.units, .valueUnit)
            try f.remove(FolioDomain.Unit.self, unit)
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
        examples: ["folio unit link EC4207/트리 10-26 10-28", "folio unit link EC4207/트리 10-28 --off --dry-run"],
        phrases: ["단원과 수업 연결", "이 수업에서 배운 단원"])
public struct UnitLink {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 회차. 예: 10-26
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

// MARK: Lecture sections

/// Checks one unit's pages of a lecture file before anything is written.
func checkPages(_ first: Int, _ last: Int) throws {
    guard first >= 1, first <= last else { throw ActionError.rule(String(localized: .errorUnitPagesRange(first, last))) }
}

@Action("unit pages add", "단원에 렉처 파일의 쪽 구간 더하기. 한 단원이 여러 파일에, 한 파일이 여러 단원에 걸칠 수 있다",
        done: "단원 '{unit}'에 {material}의 쪽 구간을 더했습니다",
        examples: ["folio unit pages add EC4207/매칭 05_Matchings.pdf --first 1 --last 4"],
        phrases: ["렉처 목차", "단원 쪽 구간", "이 단원은 몇 쪽부터"])
public struct UnitPagesAdd {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 렉처 자료
    @Arg var material: Material.ID
    /// 첫 쪽
    var first: Int
    /// 끝 쪽
    var last: Int

    public func run(_ ctx: ActionContext) throws {
        try checkPages(first, last)
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            try f.update(\.units, unit) { u in
                u.lecturePages.append(UnitPages(materialId: material, firstPage: first, lastPage: last))
                u.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}

/// One range in place of every range the unit has in the file.
@Action("unit pages set", "단원의 렉처 쪽 구간 고치기. 그 파일에서 단원이 가진 구간을 이 구간 하나로 바꾼다",
        done: "단원 '{unit}'의 {material} 쪽 구간을 고쳤습니다",
        examples: ["folio unit pages set EC4207/매칭 05_Matchings.pdf --first 1 --last 6"],
        phrases: ["단원 쪽 구간 고치기", "목차 경계 옮기기"])
public struct UnitPagesSet {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 렉처 자료
    @Arg var material: Material.ID
    /// 첫 쪽
    var first: Int
    /// 끝 쪽
    var last: Int

    public func run(_ ctx: ActionContext) throws {
        try checkPages(first, last)
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            try f.update(\.units, unit) { u in
                let next = u.lecturePages.filter { $0.materialId != material } + [UnitPages(materialId: material, firstPage: first, lastPage: last)]
                guard next != u.lecturePages else { return }
                u.lecturePages = next
                u.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}

@Action("unit pages rm", "단원에서 렉처 파일의 쪽 구간 빼기. 파일과 단원은 그대로 둔다", effect: .removes,
        confirm: "단원 '{unit}'에서 {material}의 쪽 구간을 뺍니다.", done: "단원 '{unit}'에서 {material}의 쪽 구간을 뺐습니다",
        examples: ["folio unit pages rm EC4207/매칭 05_Matchings.pdf --dry-run"], phrases: ["단원 쪽 구간 지우기"])
public struct UnitPagesRemove {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 렉처 자료
    @Arg var material: Material.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            try f.update(\.units, unit) { u in
                guard u.lecturePages.contains(where: { $0.materialId == material }) else { return }
                u.lecturePages.removeAll { $0.materialId == material }
                u.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}

/// Every cut is checked before the file is changed: a unit that is missing must come with the title to make it.
func checkCuts(_ cuts: [LectureCut], in f: CourseFile) throws {
    for cut in cuts {
        try checkPages(cut.firstPage, cut.lastPage)
        guard !f.units.contains(where: { $0.id == cut.unit }) else { continue }
        guard !(cut.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ActionError.notFound(String(localized: .errorNotFoundItem(String(localized: .valueUnit))))
        }
        if let parent = cut.parent { _ = try index(parent, in: f.units, .valueUnit) }
    }
}

/// The whole split of one lecture file at once, as the split screen and the add sheet approve it: every unit's
/// pages of the file become these, and units named only by a title are made. The command names units by title, so it
/// is written by hand.
@Action("material split", "렉처 파일을 단원 구간으로 나누기. 그 파일의 단원 구간을 모두 이 목록으로 바꾸고, 없는 단원은 만든다",
        done: "{material}을(를) 단원 구간으로 나눴습니다",
        examples: [#"folio material split EC4207/05_Matchings.pdf 1-4:매칭 5-8:König 9-13:"Hall의 결혼 정리""#],
        phrases: ["단원으로 나누기", "렉처 목차 나누기", "렉처를 단원별로"], cli: .manual)
public struct MaterialSplit {
    @Arg var course: Course.ID
    @Arg var material: Material.ID
    var sections: [LectureCut]

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            try checkCuts(sections, in: f)
            f.split(material, into: sections, device: ctx.device, now: ctx.now)
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

/// What one class went through, every lecture file at once, as the end-of-class prompt saves it: one action, so a
/// range the rules refuse leaves the other files unwritten too. Files left out keep their links. The command reads
/// each file with its pages (`05_Matchings.pdf:3-12`), so it is written by hand.
@Action("session progress", "수업의 렉처 진도 기록하기. 자료마다 이번 수업이 다룬 쪽을 회차에 연결한다",
        done: "회차 '{session}'의 진도를 기록했습니다",
        examples: ["folio session progress EC4207/10-26 05_Matchings.pdf:3-12 06_Flows.pdf:1-4"],
        phrases: ["렉처 진도", "수업 진도", "어디까지 나갔", "진도 기록"], cli: .manual)
public struct SessionProgress {
    @Arg var course: Course.ID
    @Arg var session: Session.ID
    var ranges: [SessionMaterial]

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(session, in: f.sessions, .valueSession)
            for range in ranges {
                _ = try index(range.materialId, in: f.materials, .valueMaterial)
                f.linkMaterial(range.materialId, session: session, firstPage: range.firstPage, lastPage: range.lastPage)
            }
        }
    }
}

/// Everything the end-of-class wrap-up saves, in one action so a part the rules refuse leaves the rest unwritten too.
/// Marks the class wrapped up, which is what stops it being asked about: what was left empty stays so on purpose. The
/// command takes each lecture file with its pages, as `session progress` does, so it is written by hand.
@Action("session wrap-up", "수업 정리. 회차의 렉처 진도, 단원, 출결을 한 번에 적고 정리했다고 표시한다",
        done: "회차 '{session}'을(를) 정리했습니다",
        examples: [#"folio session wrap-up EC4207/10-26 05_Matchings.pdf:3-12 --unit 매칭 --attendance late --dry-run"#],
        phrases: ["수업 정리", "수업 끝", "오늘 수업 정리", "수업 마무리"], cli: .manual)
public struct SessionWrapUp {
    @Arg var course: Course.ID
    @Arg var session: Session.ID
    /// 렉처 파일마다 이번 수업이 다룬 쪽. 적지 않은 파일의 연결은 그대로 둔다
    var ranges: [SessionMaterial]
    /// 회차의 단원. 이것으로 바뀐다
    var units: [FolioDomain.Unit.ID]
    /// 출결
    var attendance: AttendanceState

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            let i = try index(session, in: f.sessions, .valueSession)
            for range in ranges {
                _ = try index(range.materialId, in: f.materials, .valueMaterial)
                f.linkMaterial(range.materialId, session: session, firstPage: range.firstPage, lastPage: range.lastPage)
            }
            for unit in units { _ = try index(unit, in: f.units, .valueUnit) }
            for unit in Set(f.sessions[i].unitIds).symmetricDifference(units) { f.toggle(session: session, unit: unit) }
            f.attendance.removeAll { $0.sessionId == session }
            if attendance != .present { f.attendance.append(Attendance(device: ctx.device, at: ctx.now, sessionId: session, state: attendance)) }
            f.sessions[i].isWrappedUp = true
        }
    }
}

/// Called by the app when a recording ends. Only files the session has no link to are linked: a range the user set
/// stays, and a lecture that returned to an earlier file would otherwise shrink its range to what this class saw.
@Action("session link-viewed", "녹음 중 본 강의 페이지를 회차에 연결하기. 연결이 없는 자료만 더하고 있는 연결은 그대로 둔다",
        discussion: "앱 안의 PDF 보기에서 20초 이상 머문 페이지의 처음부터 끝까지가 범위다. 녹음이 끝나면 앱이 부른다.",
        done: "회차 '{session}'에 녹음 중 본 페이지를 연결했습니다",
        examples: ["folio session link-viewed EC4207/10-26 --dry-run"], phrases: ["녹음 중 본 페이지", "본 페이지 연결", "수업 중 본 슬라이드"])
public struct SessionLinkViewed {
    @Arg var course: Course.ID
    /// 회차
    @Arg var session: Session.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(session, in: f.sessions, .valueSession)
            for recording in f.recordings where recording.sessionId == session { f.linkViewedPages(of: recording) }
        }
    }
}
