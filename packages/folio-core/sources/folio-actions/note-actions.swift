import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

func note(_ ctx: ActionContext, course: UUID, path: String) throws -> NoteFile {
    guard let note = try ctx.store(course).note(at: path) else {
        throw ActionError.notFound(String(localized: .errorNotFoundNote("\(path)")))
    }
    return note
}

func note(_ ctx: ActionContext, course: UUID, id: UUID) throws -> NoteFile {
    guard let note = try ctx.store(course).note(id: id) else { throw ActionError.notFound(String(localized: .errorNotFoundNote("\(id)"))) }
    return note
}

/// A note in `Notes/` with `body`, or the template for its kind. The command reads the body from a file or standard
/// input, so it is written by hand.
@Action("note add", "Notes 폴더에 노트 만들기. 본문을 주지 않으면 종류의 템플릿", effect: .creates, done: "노트 '{title}'을(를) 만들었습니다",
        phrases: ["노트 만들기", "새 노트", "정리 노트 쓰기"], cli: .manual)
public struct NoteAdd {
    @New var id: Note.ID
    @Arg var course: Course.ID
    @Arg var title: String
    var kind: NoteKind = .free
    var body: String?

    public func run(_ ctx: ActionContext) throws {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { throw ActionError.rule(String(localized: .errorNoteTitleEmpty)) }
        let settings = try ctx.settings()
        let body = body ?? NoteTemplate.body(for: kind, title: title, sections: settings.noteSections(for: kind))
        ctx.made(try ctx.createNote(course, title: title, meta: NoteMeta(id: id, kind: kind, math: settings.newNoteMath), body: body) ?? id)
    }
}

/// Writes the whole file, frontmatter included. With `expected`, refuses when the file is no longer that text: it was
/// changed elsewhere since it was read. The command reads the text from a file and checks `--expect` against a hash.
@Action("note write", "노트 파일 전체를 바꾸기. frontmatter까지 그대로 쓴다", done: "노트 '{note}'을(를) 썼습니다",
        phrases: ["노트 수정", "노트 내용 바꾸기"], cli: .manual)
public struct NoteWrite {
    @Arg var course: Course.ID
    @Arg var note: Note.Path
    var text: String
    var expected: String?

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try FolioActions.note(ctx, course: course, path: note)
        if let expected, try store.read(file) != expected { throw ActionError.conflict(String(localized: .errorNoteChanged("\(note)"))) }
        try ctx.io(Change(.changed, ctx.relative(file.url))) { try store.write(file, text: text) }
    }
}

/// Gives a note made outside Folio an id in its frontmatter, so sessions and searches can point at it.
@Action("note adopt", "Folio 밖에서 만든 노트에 ID 붙이기", done: "노트 '{note}'에 ID를 붙였습니다",
        examples: ["folio note adopt EC4207/Notes/외부.md"], phrases: ["밖에서 만든 노트 등록"])
public struct NoteAdopt {
    /// 과목
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.Path

    public func run(_ ctx: ActionContext) throws {
        let file = try FolioActions.note(ctx, course: course, path: note)
        if let id = file.meta.id {
            ctx.made(id)
            return
        }
        let store = try ctx.store(course)
        ctx.made(try ctx.io(Change(.changed, ctx.relative(file.url))) { try store.ensureID(file) } ?? UUID())
    }
}

/// One kind at a time: becoming another kind lets go of the session or exam the old one belonged to. Writes the
/// frontmatter and the session's note link together. The command takes each unit as `--unit`, so it is written by hand.
@Action("note link", "노트의 종류와 회차·시험·단원 연결 정하기", done: "노트 '{note}'을(를) 연결했습니다",
        phrases: ["노트 연결", "노트 종류"], cli: .manual)
public struct NoteLink {
    @Arg var course: Course.ID
    @Arg var note: Note.ID
    var kind: NoteKind
    var session: Session.ID?
    var exam: Exam.ID?
    var units: [FolioDomain.Unit.ID] = []

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let course = try ctx.file(self.course)
        // The note's frontmatter isn't part of the course file, so the model can't check where it points.
        if kind == .rough || kind == .review, let session {
            guard let s = course.sessions.first(where: { $0.id == session }) else { throw ActionError.notFound(String(localized: .errorNotFoundSession)) }
            if s.isCancelled { throw ActionError.rule(String(localized: .errorNoteCancelledSession)) }
        }
        if kind == .examSummary, let exam, !course.exams.contains(where: { $0.id == exam }) { throw ActionError.notFound(String(localized: .errorNotFoundExam)) }
        if kind == .topic, let u = units.first(where: { u in !course.units.contains { $0.id == u } }) { throw ActionError.notFound(String(localized: .errorNotFoundUnitId("\(u)"))) }
        var file = try FolioActions.note(ctx, course: self.course, id: note)
        file.meta.kind = kind
        file.meta.sessionId = kind == .rough || kind == .review ? session : nil
        file.meta.examId = kind == .examSummary ? exam : nil
        file.meta.unitIds = kind == .topic ? units : file.meta.unitIds
        let text = try store.read(file)
        try ctx.io(Change(.changed, ctx.relative(file.url))) { try store.save(file, text: text) }
        try ctx.edit(self.course) { $0.linkNote(note, to: file.meta.sessionId, as: kind) }
    }
}

/// Sessions let go of the note first: a note left behind by a failed trash is harmless, a link to nothing is not.
/// The note goes to the Trash; its images stay in `assets/`, which other notes may share.
@Action("note rm", "노트를 휴지통으로. 회차의 연결도 뗀다", discussion: "그림은 assets에 남는다.", effect: .removes,
        confirm: "{note}을(를) 휴지통으로 옮깁니다.", done: "{note}을(를) 휴지통으로 옮겼습니다",
        examples: [#"folio note rm "EC4207/시험 메모" --dry-run"#], phrases: ["노트 삭제"])
public struct NoteRemove {
    /// 과목
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.Path

    public func run(_ ctx: ActionContext) throws {
        let file = try FolioActions.note(ctx, course: course, path: note)
        if let id = file.meta.id { try ctx.edit(course) { $0.forgetNote(id) } }
        let store = try ctx.store(course)
        try ctx.io(Change(.removed, ctx.relative(file.url))) { try store.trashNote(file) }
    }
}

// MARK: Quiz

/// Adds cards or replaces those with the same id. `movedFrom` is the unit an edited card left; it is taken out there
/// only after the new copy is saved. The command reads the cards from a JSON file.
@Action("quiz add", "JSON 파일의 카드를 넣거나 같은 ID의 카드를 바꾸기", done: "카드 {cards}을(를) 저장했습니다",
        phrases: ["카드 만들기", "퀴즈 추가"], cli: .manual)
public struct QuizCardSave {
    @Arg var course: Course.ID
    var cards: [QuizCard]
    var movedFrom: FolioDomain.Unit.ID?

    public func run(_ ctx: ActionContext) throws {
        let units = Set(try ctx.file(course).units.map(\.id))
        for unit in Set(cards.map(\.unitId)) {
            guard units.contains(unit) else { throw ActionError.notFound(String(localized: .errorNotFoundUnit)) }
            try ctx.editQuiz(course, unit: unit) { list in
                for var card in cards where card.unitId == unit {
                    card.touch(by: ctx.device, at: ctx.now)
                    if let i = list.firstIndex(where: { $0.id == card.id }) { list[i] = card } else { list.append(card) }
                }
            }
        }
        if let movedFrom, !cards.contains(where: { $0.unitId == movedFrom }) {
            let ids = Set(cards.map(\.id))
            try ctx.editQuiz(course, unit: movedFrom) { $0.removeAll { ids.contains($0.id) } }
        }
    }
}

/// Past attempts stay in the log. The command finds the card by its prompt among the unit's cards.
@Action("quiz rm", "카드 지우기. 풀이 기록은 남는다", effect: .removes, confirm: "단원 '{unit}'의 카드를 지웁니다. 풀이 기록은 남습니다.",
        done: "단원 '{unit}'의 카드를 지웠습니다", phrases: ["카드 삭제"], cli: .manual)
public struct QuizCardRemove {
    @Arg var course: Course.ID
    @Arg var unit: FolioDomain.Unit.ID
    @Arg var card: QuizCard.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.editQuiz(course, unit: unit) { list in
            _ = try index(card, in: list, .valueCard)
            list.removeAll { $0.id == card }
        }
    }
}

@Action("quiz record", "카드 풀이 결과를 기록", effect: .logs, done: "풀이를 기록했습니다",
        phrases: ["맞았", "틀렸", "맞힘", "퀴즈 풀이", "맞음", "틀림", "카드 결과"], cli: .manual)
public struct QuizRecord {
    @Arg var course: Course.ID
    var attempt: QuizAttemptEvent

    public func run(_ ctx: ActionContext) throws {
        let units = try ctx.file(course).units
        guard try units.contains(where: { try ctx.store(course).loadQuiz(unit: $0.id).model.cards.contains { $0.id == attempt.cardId } }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundCard))
        }
        try ctx.log(attempt, course: course)
    }
}

/// A new set, or the whole of one with the same id. The command builds the set from problem numbers.
@Action("problem-set add", "문제 번호로 문제 묶음 만들기", effect: .creates, done: "문제 묶음을 저장했습니다",
        phrases: ["문제 묶음 만들기", "연습문제 등록"], cli: .manual)
public struct ProblemSetSave {
    @Arg var course: Course.ID
    var set: ProblemSet

    public func run(_ ctx: ActionContext) throws {
        var set = set
        set.touch(by: ctx.device, at: ctx.now)
        try ctx.edit(course) { f in
            if let i = f.problemSets.firstIndex(where: { $0.id == set.id }) { f.problemSets[i] = set } else { f.problemSets.append(set) }
        }
        ctx.made(set.id)
    }
}

/// The number grid and unit links go; problem and solution files and past attempts stay.
@Action("problem-set rm", "문제 묶음 지우기. 문제 파일과 풀이 기록은 남는다", effect: .removes,
        confirm: "문제 묶음 '{set}'을(를) 지웁니다. 문제 파일과 풀이 기록은 남습니다.", done: "문제 묶음 '{set}'을(를) 지웠습니다",
        examples: [#"folio problem-set rm "EC4207/Exercise 1" --dry-run"#], phrases: ["문제 묶음 삭제"])
public struct ProblemSetRemove {
    /// 과목
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(set, in: f.problemSets, .valueProblemSet)
            f.problemSets.removeAll { $0.id == set }
        }
    }
}

@Action("problem-set link", "문제를 단원에 연결하거나 떼기", done: "문제 묶음 '{set}'의 {number}번과 단원 '{unit}'의 연결을 바꿨습니다",
        examples: [#"folio problem-set link "EC4207/Exercise 1" 3a 매칭"#, #"folio problem-set link "EC4207/Exercise 1" 3a 매칭 --off"#],
        phrases: ["문제 단원 연결"])
public struct ProblemLinkUnit {
    /// 과목
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID
    /// 문제 번호
    @Arg var number: String
    /// 같은 과목의 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 연결 떼기
    @Off("off") var linked = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            let s = try index(set, in: f.problemSets, .valueProblemSet)
            _ = try index(unit, in: f.units, .valueUnit)
            guard let p = f.problemSets[s].problems.firstIndex(where: { $0.number == number }) else { throw ActionError.notFound(String(localized: .errorNotFoundProblem(number))) }
            guard f.problemSets[s].problems[p].unitIds.contains(unit) != linked else { return }
            if linked { f.problemSets[s].problems[p].unitIds.append(unit) } else { f.problemSets[s].problems[p].unitIds.removeAll { $0 == unit } }
            f.problemSets[s].touch(by: ctx.device, at: ctx.now)
        }
    }
}

@Action("problem-set record", "문제 풀이 결과를 기록", effect: .logs, done: "풀이를 기록했습니다",
        phrases: ["풀었", "못 풀", "문제 풀이 결과", "풀었음", "못 풂"], cli: .manual)
public struct ProblemRecord {
    @Arg var course: Course.ID
    var attempt: ProblemAttemptEvent

    public func run(_ ctx: ActionContext) throws {
        guard let set = try ctx.file(course).problemSets.first(where: { $0.id == attempt.problemSetId }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundProblemSet))
        }
        guard set.problems.contains(where: { $0.number == attempt.number }) else { throw ActionError.notFound(String(localized: .errorNotFoundProblem(attempt.number))) }
        try ctx.log(attempt, course: course)
    }
}

// MARK: Review

/// The review result and the time spent, in this device's log.
@Action("review record", "단원 복습 결과와 걸린 시간을 기록", effect: .logs, done: "단원 '{unit}'의 복습을 기록했습니다",
        examples: [#"folio review record EC4207/매칭 good --start "2026-10-28 20:00" --end "2026-10-28 20:40""#],
        phrases: ["복습했", "공부했", "복습 완료", "복습 기록", "공부함"])
public struct ReviewRecord {
    /// 과목
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 결과
    @Arg var result: ReviewResult
    /// 시작 시각
    var start: Date
    /// 끝난 시각
    var end: Date

    public func run(_ ctx: ActionContext) throws {
        guard end >= start else { throw ActionError.rule(String(localized: .errorReviewEndBeforeStart)) }
        try ctx.log(ReviewEvent(unitId: unit, result: result, seconds: Int(end.timeIntervalSince(start).rounded())), course: course, at: end)
        try ctx.log(StudySessionEvent(courseId: course, start: start, end: end, screen: "review"), course: course, at: end)
    }
}

/// Marks units as not needing review, one `skip` event each, with no study time. Units may come from several courses,
/// so the command is written by hand.
@Action("review skip", "단원을 복습하지 않아도 되는 것으로 표시. 여러 개면 확인을 받는다", effect: .logs,
        confirm: "단원 {units}의 복습을 건너뜁니다.", done: "단원 {units}을(를) 건너뛰었습니다",
        phrases: ["복습 안 해도", "복습 빼기", "복습 건너뛰기", "복습 필요 없음"], cli: .manual)
public struct ReviewSkip {
    public struct Target: Codable, Sendable, Equatable {
        public var course: UUID
        public var unit: UUID
        public init(course: UUID, unit: UUID) {
            self.course = course
            self.unit = unit
        }
    }
    var units: [Target]

    public func run(_ ctx: ActionContext) throws {
        for t in units { try ctx.log(ReviewEvent(unitId: t.unit, result: .skip, seconds: 0), course: t.course) }
    }
}
