import ArgumentParser
import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation

extension Resolver {
    func id(_ kind: ItemKind, _ ref: String, in course: CourseRef? = nil, parent: UUID? = nil) throws -> UUID {
        try named(kind, ref, in: course, parent: parent).id
    }

    // 이름은 사람에게 보이는 이름이다(`folio link`의 제목). 과목 안의 종류는 과목 코드를 붙이지 않는다.
    func named(_ kind: ItemKind, _ ref: String, in course: CourseRef? = nil, parent: UUID? = nil) throws -> (id: UUID, name: String) {
        let ref = course?.local(ref) ?? ref
        func scoped() throws -> CourseRef {
            guard let course else { throw CLIError(exit: .usage, message: String(localized: .resolveNeedCourse(ref))) }
            return course
        }
        switch kind {
        case .course:
            let c = try self.course(ref)
            return (c.id, "\(c.code) \(c.course.title)")
        case .semester:
            let s = try semester(ref)
            return (s.id, s.folder?.name ?? s.source ?? s.id.uuidString)
        case .session:
            let c = try scoped()
            let s = try session(ref, in: c)
            return (s.id, c.file.title(of: s, calendar: ctx.calendar))
        case .exam: let e = try exam(ref, in: scoped()); return (e.id, e.title)
        case .unit: let u = try unit(ref, in: scoped()); return (u.id, u.title)
        case .assignment: let a = try assignment(ref, in: scoped()); return (a.id, a.title)
        case .gradeComponent: let g = try component(ref, in: scoped()); return (g.id, g.name)
        case .scoreEntry: let e = try score(ref, in: scoped()); return (e.id, e.title)
        case .material: let m = try material(ref, in: scoped()); return (m.id, m.path)
        case .problemSet: let p = try problemSet(ref, in: scoped()); return (p.id, p.title)
        case .note:
            let c = try scoped()
            let n = try note(ref, in: c)
            return (try noteID(of: n, ref, in: c), n.title)
        case .recording: let r = try recording(ref, in: scoped()); return (r.id, (r.file as NSString).lastPathComponent)
        case .letterGrade: let g = try letterGrade(ref); return (g.id, g.symbol)
        case .courseCode: let c = try code(ref); return (c.id, c.prefix)
        case .person: let p = try person(ref); return (p.id, p.name)
        case .category: let c = try category(ref); return (c.id, c.name)
        case .examPlanItem: let i = try planItem(ref, exam: parent, in: scoped()); return (i.id, i.title)
        case .studyCard: let q = try card(ref, unit: parent, in: scoped()); return (q.id, q.front)
        case .problem: let p = try problem(ref, set: parent, in: scoped()); return (p.id, p.number)
        case .noteWidget: let w = try widget(ref, in: scoped()); return (w, w.uuidString)
        case .moveBatch:
            guard let id = UUID(uuidString: ref) else { throw CLIError(exit: .usage, message: String(localized: .resolveNotBatch(ref))) }
            return (id, id.uuidString)
        case .notePath: throw CLIError(exit: .usage, message: String(localized: .resolveKindNoName(kind.rawValue)))
        }
    }

    func planItem(_ ref: String, exam: UUID?, in c: CourseRef) throws -> ExamPlanItem {
        if let exam {
            guard let e = c.file.exams.first(where: { $0.id == exam }) else {
                throw CLIError(exit: .notFound, message: String(localized: .resolveNotFound(ItemKind.exam.noun, exam.uuidString)))
            }
            return try planItem(ref, in: e, course: c)
        }
        let items = c.file.exams.flatMap { e in e.plan.map { (e, $0) } }
        return try pick(
            ref, items, what: ItemKind.examPlanItem.noun, id: { $0.1.id }, names: { [$0.1.title] },
            ref: { "\(c.code)/\($0.0.title) \($0.1.title)" }
        ).1
    }

    func card(_ ref: String, unit: UUID?, in c: CourseRef) throws -> StudyCard {
        let units = unit.map { id in c.file.units.filter { $0.id == id } } ?? c.file.units
        if let unit, units.isEmpty {
            throw CLIError(exit: .notFound, message: String(localized: .resolveNotFound(ItemKind.unit.noun, unit.uuidString)))
        }
        let cards = try units.flatMap { try c.store.loadCards(unit: $0.id).model.cards }
        return try pick(ref, cards, what: ItemKind.studyCard.noun, names: { [$0.front] }, ref: { $0.id.uuidString })
    }

    // 문제는 묶음 안의 번호로 부른다. 묶음 없이 부르면 과목의 모든 묶음에서 찾는다.
    func problem(_ ref: String, set: UUID?, in c: CourseRef) throws -> Problem {
        let sets = set.map { id in c.file.problemSets.filter { $0.id == id } } ?? c.file.problemSets
        if let set, sets.isEmpty {
            throw CLIError(exit: .notFound, message: String(localized: .resolveNotFound(ItemKind.problemSet.noun, set.uuidString)))
        }
        let problems = sets.flatMap { s in s.problems.map { (s, $0) } }
        return try pick(
            ref, problems, what: ItemKind.problem.noun, id: { $0.1.id }, names: { [$0.1.number] },
            ref: { "\(c.code)/\($0.0.title) \($0.1.number)" }
        ).1
    }

    func widget(_ ref: String, in c: CourseRef) throws -> UUID {
        guard let id = UUID(uuidString: ref) else { throw CLIError(exit: .usage, message: String(localized: .resolveNotWidget(ref))) }
        guard FileManager.default.fileExists(atPath: c.store.fileURL(NoteWidget.path(id)).path) else {
            throw CLIError(exit: .notFound, message: String(localized: .resolveNotFound(ItemKind.noteWidget.noun, id.uuidString)))
        }
        return id
    }

    func noteID(_ ref: String, in c: CourseRef) throws -> UUID { try noteID(of: try note(ref, in: c), ref, in: c) }

    func noteID(of n: NoteFile, _ ref: String, in c: CourseRef) throws -> UUID {
        guard let id = n.meta.id else {
            let path = c.store.coursePath(of: n.url) ?? ref
            throw CLIError(exit: .rule, message: String(localized: .resolveNoteNoId(path)), hints: ["folio note adopt \(c.code)/\(path)"])
        }
        return id
    }

    func path(_ kind: ItemKind, _ ref: String, in course: CourseRef?) throws -> String {
        guard let course else { throw CLIError(exit: .usage, message: String(localized: .resolveNeedCourse(ref))) }
        guard kind.byPath else { throw CLIError(exit: .usage, message: String(localized: .resolveKindNoPath(kind.rawValue))) }
        let n = try note(course.local(ref), in: course)
        return course.store.coursePath(of: n.url) ?? ref
    }
}

extension Resolver {
    func parse<T: CLIText>(_ text: String, in course: CourseRef?) throws -> T { try T(cli: text, self, in: course) }
}

// 파일이나 항목 이름에는 콜론이 들 수 있지만 그 뒤의 숫자에는 들지 않으므로 마지막 콜론에서 나눈다.
private func pair(_ text: String, _ error: @autoclosure () -> String) throws -> (String, String) {
    guard let i = text.lastIndex(of: ":") else { throw CLIError(exit: .usage, message: error()) }
    return (String(text[..<i]), String(text[text.index(after: i)...]))
}

private func scoped(_ course: CourseRef?, _ text: String) throws -> CourseRef {
    guard let course else { throw CLIError(exit: .usage, message: String(localized: .resolveNeedCourse(text))) }
    return course
}

extension SessionMaterial: CLIText {
    init(cli text: String, _ r: Resolver, in course: CourseRef?) throws {
        let c = try scoped(course, text)
        let (name, pages) = try pair(text, String(localized: .sessionProgressFormat(text)))
        let bounds = pages.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...2).contains(bounds.count), let first = bounds.first ?? nil, let last = bounds.last ?? nil else {
            throw CLIError(exit: .usage, message: String(localized: .sessionProgressFormat(text)))
        }
        self.init(materialId: try r.material(c.local(name), in: c).id, firstPage: first, lastPage: last)
    }
}

extension AttendanceCap: CLIText {
    init(cli text: String, _ r: Resolver, in course: CourseRef?) throws {
        let (n, grade) = try pair(text, String(localized: .componentPolicyBadPair(text)))
        guard let absences = Int(n) else { throw CLIError(exit: .usage, message: String(localized: .componentPolicyBadAbsences(text))) }
        self.init(absences: absences, maxGrade: try r.letterGrade(grade).id)
    }
}

extension GradeCutoff: CLIText {
    init(cli text: String, _ r: Resolver, in course: CourseRef?) throws {
        let (grade, n) = try pair(text, String(localized: .componentPolicyBadPair(text)))
        guard let min = Double(n) else { throw CLIError(exit: .usage, message: String(localized: .componentPolicyBadMinScore(text))) }
        self.init(grade: try r.letterGrade(grade).id, minScore: min)
    }
}

extension LateRule: CLIText {
    init(cli text: String, _ r: Resolver, in course: CourseRef?) throws {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        let days = parts.count == 2 ? Int(parts[1]) : nil
        guard (1...2).contains(parts.count), let percent = Double(parts[0]), parts.count == 1 || days != nil else {
            throw CLIError(exit: .usage, message: String(localized: .lateRuleFormat(text)))
        }
        self.init(percentPerDay: percent, days: days)
    }

    var cliText: String { percentPerDay.formatted() + (days.map { ":\($0)" } ?? "") }

    var summary: String { acceptsLate ? cliText : String(localized: .lateRuleNotAccepted(cliText)) }
}

extension StudentProgram: CLIText {
    init(cli text: String, _ r: Resolver, in course: CourseRef?) throws {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = StudentProgram.Kind(rawValue: parts[0]) else {
            throw CLIError(
                exit: .usage, message: String(localized: .requirementSetBadProgram(text)),
                hints: [
                    String(localized: .requirementSetProgramKinds) + StudentProgram.Kind.allCases.map(\.rawValue).joined(separator: ", ")
                ])
        }
        self.init(codeId: try r.code(parts[1]).id, kind: kind)
    }
}

extension AssignmentSave.Score: CLIText {
    init(cli text: String, _ r: Resolver, in course: CourseRef?) throws {
        let c = try scoped(course, text)
        let (target, value) = text.firstIndex(of: ":").map { (String(text[..<$0]), String(text[text.index(after: $0)...])) } ?? (nil, text)
        let parts = value.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2 else { throw CLIError(exit: .usage, message: String(localized: .assignmentSetScoreFormat(text))) }
        self.init(component: try target.map { try r.component($0, in: c).id }, score: parts[0], max: parts[1])
    }
}

extension Complete {
    static func ref(_ kind: ItemKind) -> CompletionKind {
        switch kind {
        case .course: .custom(courses)
        case .semester: .custom(semesters)
        case .session: sessions
        case .exam: exams
        case .unit: units
        case .assignment: assignments
        case .gradeComponent: components
        case .material: materials
        case .problemSet: problemSets
        case .note, .notePath: notes
        case .scoreEntry, .noteWidget, .recording, .examPlanItem, .studyCard, .problem, .letterGrade, .courseCode, .person, .category,
            .moveBatch:
            .default
        }
    }
}

@discardableResult
func perform<A: Action>(spec action: A, _ options: GlobalOptions, ctx: ActionContext, read: JSONValue? = nil) throws -> ActionContext {
    let spec = A.spec
    if let record = Built.record { record(A.command, try JSONValue(action)) }
    let confirm = spec.asks(action) ? spec.confirm.map { spec.render($0, action, ctx: ctx) } : nil
    let before = spec.effect == .creates ? nil : spec.render(spec.done, action, ctx: ctx)
    let result = try perform(
        action, options, ctx: ctx, done: before ?? spec.render(spec.done, action, ctx: ctx), confirm: confirm, read: read)
    if spec.undoable, !options.json, let batch = result.made { say(String(localized: .performUndoHint(batch.uuidString)).styled(.dim)) }
    return result
}

func readJSONFile<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
    let data: Data
    if path == "-" {
        data = FileHandle.standardInput.readDataToEndOfFile()
    } else {
        guard let read = try? Data(contentsOf: URL(filePath: absolute(path))) else {
            throw CLIError(exit: .usage, message: String(localized: .importUnreadable(path)))
        }
        data = read
    }
    do {
        return try JSONDecoder.folio.decode(T.self, from: data)
    } catch let e as DecodingError {
        throw CLIError(exit: .usage, message: String(localized: .importBadFormat(path, RunCommand.describe(e))))
    }
}
