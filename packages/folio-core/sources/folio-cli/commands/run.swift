import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run", abstract: "액션 하나를 JSON 입력으로 실행. 에이전트용",
        discussion: """
            입력의 필드는 `folio actions --schema`가 알려 준다. 항목을 가리키는 필드(course, session, exam, unit, material,
            component, assignment, set, note, semester)는 UUID와 이름을 모두 받는다. 형식이 틀리면 어느 필드가 틀렸는지
            알려 주고 종료 코드 2로 끝난다.

            예시:
              folio run session add --input '{"course":"EC4207","date":"2026-10-28T10:30:00+09:00"}'
              echo '{"course":"EC4207","title":"트리"}' | folio run unit add --input - --dry-run
            """)

    @OptionGroup var g: GlobalOptions
    // Unrecognized words stay in the name, so `exam scope --taught` names its action.
    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("액션의 명령 이름. 예: session add", valueName: "action")) var action: [String]
    @Option(help: ArgumentHelp("입력 JSON. -이면 표준 입력", valueName: "JSON")) var input: String

    func run() throws {
        let name = action.joined(separator: " ")
        guard let type = Actions.all.first(where: { $0.command == name }) else {
            throw CLIError(exit: .usage, message: "없는 액션입니다: \(name)", candidates: Actions.all.map { $0.command }.filter { $0.hasPrefix(action.first ?? "") })
        }
        let text = input == "-" ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) : input
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else {
            throw CLIError(exit: .usage, message: "입력이 JSON이 아닙니다")
        }
        try execute(type, json, try CLI.context(g))
    }

    func execute<A: Action>(_ type: A.Type, _ json: JSONValue, _ ctx: ActionContext) throws {
        guard case .object(var o) = json else { throw CLIError(exit: .usage, message: "입력은 JSON 객체여야 합니다") }
        let r = Resolver(ctx)
        var course: CourseRef?
        // The course comes first: the other items are looked up inside it.
        for f in A.spec.fields.sorted(by: { ($0.ref == "Course" ? 0 : 1) < ($1.ref == "Course" ? 0 : 1) }) {
            if f.role == .new {
                if o[f.name] == nil { o[f.name] = .string(UUID().uuidString) }
                continue
            }
            guard let kind = f.ref, let v = o[f.name] else { continue }
            o[f.name] = try Self.strings(v) { s in
                if kind == "Course" {
                    let c = try r.course(s)
                    course = course ?? c
                    return c.id.uuidString
                }
                if kind.hasSuffix("Path") { return try r.path(kind, s, in: course) }
                return UUID(uuidString: s) != nil ? s : try r.id(kind, s, in: course).uuidString
            }
        }
        // A whole file's decoder fills a missing key with its default: `{"settings":{}}` would reset every setting.
        if let (key, current) = try Self.wholeFile(A.command, ctx), let given = o[key] { o[key] = current.overlaid(with: given) }
        try perform(spec: try A.decode(JSONEncoder().encode(JSONValue.object(o))), g, ctx: ctx)
    }

    static func strings(_ v: JSONValue, _ f: (String) throws -> String) throws -> JSONValue {
        switch v {
        case .string(let s): .string(try f(s))
        case .array(let items): .array(try items.map { try strings($0, f) })
        default: v
        }
    }

    static func wholeFile(_ name: String, _ ctx: ActionContext) throws -> (String, JSONValue)? {
        func json(_ v: some Encodable) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder.folio.encode(v)) }
        return switch name {
        case CatalogSet.command: ("catalog", try json(ctx.catalog()))
        case SettingsSet.command: ("settings", try json(ctx.settings()))
        case GraduationSet.command: ("rule", try json(ctx.transcript().graduation))
        default: nil
        }
    }

    static func describe(_ e: DecodingError) -> String {
        let path = { (c: DecodingError.Context) in c.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".") }
        return switch e {
        case .keyNotFound(let key, let c): "\(([path(c)] + [key.stringValue]).filter { !$0.isEmpty }.joined(separator: "."))이(가) 없습니다"
        case .typeMismatch(let t, let c): "\(path(c))의 형식이 \(t)이 아닙니다"
        case .valueNotFound(let t, let c): "\(path(c))에 \(t) 값이 없습니다"
        case .dataCorrupted(let c): "\(path(c)): \(c.debugDescription)"
        @unknown default: "\(e)"
        }
    }
}

extension Action {
    static func decode(_ json: Data) throws -> Self {
        do {
            return try JSONDecoder.folio.decode(Self.self, from: json)
        } catch let error as DecodingError {
            throw CLIError(exit: .usage, message: "입력이 맞지 않습니다: \(RunCommand.describe(error))", hints: ["folio actions --schema로 형식 확인"])
        }
    }
}

extension JSONValue {
    /// Objects merge key by key; anything else, arrays included, is replaced.
    func overlaid(with patch: JSONValue) -> JSONValue {
        guard case .object(var base) = self, case .object(let p) = patch else { return patch }
        for (k, v) in p { base[k] = base[k].map { $0.overlaid(with: v) } ?? v }
        return .object(base)
    }
}
