import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

// What the generated commands (generated/commands.swift) call: one lookup and one completion per kind of item, so a
// new action's command needs no code of its own.

extension Resolver {
    func id(_ kind: String, _ ref: String, in course: CourseRef? = nil) throws -> UUID {
        // A second item in the same course may be written with or without `<course>/` in front.
        let ref = course?.local(ref) ?? ref
        func scoped() throws -> CourseRef {
            guard let course else { throw CLIError(exit: .usage, message: "과목을 함께 적어 주세요: <과목>/\(ref)") }
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
        default: throw CLIError(exit: .usage, message: "이 종류는 이름으로 가리킬 수 없습니다: \(kind)")
        }
    }

    func noteID(_ ref: String, in c: CourseRef) throws -> UUID {
        let n = try note(ref, in: c)
        guard let id = n.meta.id else {
            let path = c.store?.coursePath(of: n.url) ?? ref
            throw CLIError(exit: .rule, message: "노트에 아직 ID가 없습니다: \(path)", hints: ["folio note adopt \(c.code)/\(path)"])
        }
        return id
    }

    func path(_ kind: String, _ ref: String, in course: CourseRef?) throws -> String {
        guard let course else { throw CLIError(exit: .usage, message: "과목을 함께 적어 주세요: <과목>/\(ref)") }
        guard kind == "NotePath" else { throw CLIError(exit: .usage, message: "이 종류는 경로로 가리킬 수 없습니다: \(kind)") }
        let n = try note(course.local(ref), in: course)
        return course.store?.coursePath(of: n.url) ?? ref
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
    return try perform(action, options, ctx: ctx, done: before ?? spec.render(spec.done, action, ctx: ctx), confirm: confirm)
}

/// The action a command built, for tests that run the same input through `run --input` and directly.
enum Built {
    @TaskLocal static var record: (@Sendable (String, JSONValue) -> Void)?
}
