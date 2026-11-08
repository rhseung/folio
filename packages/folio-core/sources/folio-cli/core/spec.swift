import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

// What the generated commands (generated/commands.swift) call: one lookup and one completion per kind of item, so a
// new action's command needs no code of its own.

extension Resolver {
    /// `parent` is the item a child kind (a plan item, a card) is looked up in; without it the whole course is searched.
    func id(_ kind: String, _ ref: String, in course: CourseRef? = nil, parent: UUID? = nil) throws -> UUID {
        // A second item in the same course may be written with or without `<course>/` in front.
        let ref = course?.local(ref) ?? ref
        func scoped() throws -> CourseRef {
            guard let course else { throw CLIError(exit: .usage, message: String(localized: .resolveNeedCourse(ref))) }
            return course
        }
        return switch kind {
        case "Course": try self.course(ref).id
        case "Semester": try semester(ref).id
        case "Session": try session(ref, in: scoped()).id
        case "Exam": try exam(ref, in: scoped()).id
        case "Unit": try unit(ref, in: scoped()).id
        case "Assignment": try assignment(ref, in: scoped()).id
        case "GradeComponent": try component(ref, in: scoped()).id
        case "ScoreEntry": try score(ref, in: scoped()).id
        case "Material": try material(ref, in: scoped()).id
        case "ProblemSet": try problemSet(ref, in: scoped()).id
        case "Note": try noteID(ref, in: scoped())
        case "LetterGrade": try letterGrade(ref).id
        case "CourseCode": try code(ref).id
        case "Person": try person(ref).id
        case "Category": try category(ref).id
        case "ExamPlanItem": try planItem(ref, exam: parent, in: scoped()).id
        case "QuizCard": try card(ref, unit: parent, in: scoped()).id
        case "MoveBatch":
            // A batch has no name: `cleanup apply` and the moves print its id.
            if let id = UUID(uuidString: ref) { id } else { throw CLIError(exit: .usage, message: String(localized: .resolveNotBatch(ref))) }
        default: throw CLIError(exit: .usage, message: String(localized: .resolveKindNoName(kind)))
        }
    }

    /// In `exam`, or in every exam of the course for `run --input`, which has no exam to look in.
    func planItem(_ ref: String, exam: UUID?, in c: CourseRef) throws -> ExamPlanItem {
        if let exam {
            guard let e = c.file.exams.first(where: { $0.id == exam }) else { throw CLIError(exit: .notFound, message: String(localized: .resolveNotFound("시험", exam.uuidString))) }
            return try planItem(ref, in: e, course: c)
        }
        let items = c.file.exams.flatMap { e in e.plan.map { (e, $0) } }
        return try pick(ref, items, what: "공부 계획 항목", id: { $0.1.id }, names: { [$0.1.title] }, ref: { "\(c.code)/\($0.0.title) \($0.1.title)" }).1
    }

    /// In `unit`'s deck, or in every deck of the course.
    func card(_ ref: String, unit: UUID?, in c: CourseRef) throws -> QuizCard {
        let units = unit.map { id in c.file.units.filter { $0.id == id } } ?? c.file.units
        guard unit == nil || !units.isEmpty else { throw CLIError(exit: .notFound, message: String(localized: .resolveNotFound("단원", unit!.uuidString))) }
        let cards = try units.flatMap { try c.store.loadQuiz(unit: $0.id).model.cards }
        return try pick(ref, cards, what: "카드", names: { [$0.prompt] }, ref: { $0.id.uuidString })
    }

    func noteID(_ ref: String, in c: CourseRef) throws -> UUID {
        let n = try note(ref, in: c)
        guard let id = n.meta.id else {
            let path = c.store.coursePath(of: n.url) ?? ref
            throw CLIError(exit: .rule, message: String(localized: .resolveNoteNoId(path)), hints: ["folio note adopt \(c.code)/\(path)"])
        }
        return id
    }

    func path(_ kind: String, _ ref: String, in course: CourseRef?) throws -> String {
        guard let course else { throw CLIError(exit: .usage, message: String(localized: .resolveNeedCourse(ref))) }
        guard kind == "NotePath" else { throw CLIError(exit: .usage, message: String(localized: .resolveKindNoPath(kind))) }
        let n = try note(course.local(ref), in: course)
        return course.store.coursePath(of: n.url) ?? ref
    }
}

extension Complete {
    static func ref(_ kind: String) -> CompletionKind {
        switch kind {
        case "Course": .custom(courses)
        case "Semester": .custom(semesters)
        case "Session": sessions
        case "Exam": exams
        case "Unit": units
        case "Assignment": assignments
        case "GradeComponent": components
        case "Material": materials
        case "ProblemSet": problemSets
        case "Note", "NotePath": notes
        default: .default
        }
    }
}

@discardableResult
func perform<A: Action>(spec action: A, _ options: GlobalOptions, ctx: ActionContext) throws -> ActionContext {
    let spec = A.spec
    if let record = Built.record { record(A.command, try JSONValue(action)) }
    let confirm = spec.asks(action) ? spec.confirm.map { spec.render($0, action, ctx: ctx) } : nil
    // Rendered before running so the name of an item the action removes still shows; an item it makes has a name
    // only after.
    let before = spec.effect == .creates ? nil : spec.render(spec.done, action, ctx: ctx)
    let result = try perform(action, options, ctx: ctx, done: before ?? spec.render(spec.done, action, ctx: ctx), confirm: confirm)
    if spec.undoable, !options.json, let batch = result.made { say(String(localized: .performUndoHint(batch.uuidString)).styled(.dim)) }
    return result
}

/// The value an `@FromFile` field reads: JSON in the file at `path`, or standard input for `-`.
func readJSONFile<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
    let data: Data
    if path == "-" {
        data = FileHandle.standardInput.readDataToEndOfFile()
    } else {
        guard let read = try? Data(contentsOf: URL(filePath: absolute(path))) else { throw CLIError(exit: .usage, message: String(localized: .importUnreadable(path))) }
        data = read
    }
    do {
        return try JSONDecoder.folio.decode(T.self, from: data)
    } catch let e as DecodingError {
        throw CLIError(exit: .usage, message: String(localized: .importBadFormat(path, RunCommand.describe(e))))
    }
}

/// The action a command built, for tests that run the same input through `run --input` and directly.
enum Built {
    @TaskLocal static var record: (@Sendable (String, JSONValue) -> Void)?
}
