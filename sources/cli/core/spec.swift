import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension Resolver {
    func id(_ kind: String, _ ref: String, in course: CourseRef? = nil, parent: UUID? = nil) throws -> UUID {
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
        case "NoteWidget": try widget(ref, in: scoped())
        case "MoveBatch":
            if let id = UUID(uuidString: ref) {
                id
            } else {
                throw CLIError(exit: .usage, message: String(localized: .resolveNotBatch(ref)))
            }
        default: throw CLIError(exit: .usage, message: String(localized: .resolveKindNoName(kind)))
        }
    }

    func planItem(_ ref: String, exam: UUID?, in c: CourseRef) throws -> ExamPlanItem {
        if let exam {
            guard let e = c.file.exams.first(where: { $0.id == exam }) else {
                throw CLIError(exit: .notFound, message: String(localized: .resolveNotFound("시험", exam.uuidString)))
            }
            return try planItem(ref, in: e, course: c)
        }
        let items = c.file.exams.flatMap { e in e.plan.map { (e, $0) } }
        return try pick(
            ref, items, what: "공부 계획 항목", id: { $0.1.id }, names: { [$0.1.title] }, ref: { "\(c.code)/\($0.0.title) \($0.1.title)" }
        ).1
    }

    func card(_ ref: String, unit: UUID?, in c: CourseRef) throws -> QuizCard {
        let units = unit.map { id in c.file.units.filter { $0.id == id } } ?? c.file.units
        guard unit == nil || !units.isEmpty else {
            throw CLIError(exit: .notFound, message: String(localized: .resolveNotFound("단원", unit!.uuidString)))
        }
        let cards = try units.flatMap { try c.store.loadQuiz(unit: $0.id).model.cards }
        return try pick(ref, cards, what: "카드", names: { [$0.prompt] }, ref: { $0.id.uuidString })
    }

    func widget(_ ref: String, in c: CourseRef) throws -> UUID {
        guard let id = UUID(uuidString: ref) else { throw CLIError(exit: .usage, message: String(localized: .resolveNotWidget(ref))) }
        guard FileManager.default.fileExists(atPath: c.store.fileURL(NoteWidget.path(id)).path) else {
            throw CLIError(exit: .notFound, message: String(localized: .resolveNotFound("위젯", id.uuidString)))
        }
        return id
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

protocol CLIText {
    init(cli text: String, _ r: Resolver, in course: CourseRef?) throws
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

enum Built {
    @TaskLocal static var record: (@Sendable (String, JSONValue) -> Void)?
}
