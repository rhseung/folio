import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run", abstract: String(localized: .runAbstract),
        discussion: String(localized: .runDiscussion))

    @OptionGroup var g: GlobalOptions
    @Argument(parsing: .allUnrecognized, help: ArgumentHelp(String(localized: .runHelpAction), valueName: "action")) var action: [String]
    @Option(help: ArgumentHelp(String(localized: .runHelpInput), valueName: "JSON")) var input: String

    func run() throws {
        let name = action.joined(separator: " ")
        let text = input == "-" ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) : input
        func json() throws -> JSONValue {
            guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else {
                throw CLIError(exit: .usage, message: String(localized: .runNotJson))
            }
            return json
        }
        if let type = Actions.all.first(where: { $0.command == name }) { return try execute(type, try json(), try CLI.context(g)) }
        if let type = Queries.all.first(where: { $0.spec.command == name }) as? any QueryOutput.Type {
            return try read(type, try json(), try CLI.context(g))
        }
        throw CLIError(
            exit: .usage, message: String(localized: .runUnknownAction(name)),
            candidates: (Actions.all.map { $0.command } + Queries.all.map { $0.spec.command }).filter { $0.hasPrefix(action.first ?? "") })
    }

    func execute<A: Action>(_ type: A.Type, _ json: JSONValue, _ ctx: ActionContext) throws {
        var o = try Self.resolved(json, A.spec.fields, ctx)
        if let (key, current) = try A.currentFile(ctx), let given = o[key] { o[key] = current.overlaid(with: given) }
        try perform(spec: try decodeInput(A.self, JSONEncoder().encode(JSONValue.object(o))), g, ctx: ctx)
    }

    func read<Q: QueryOutput>(_ type: Q.Type, _ json: JSONValue, _ ctx: ActionContext) throws {
        let o = try Self.resolved(json, Q.spec.fields, ctx)
        try show(try decodeInput(Q.self, JSONEncoder().encode(JSONValue.object(o))), g, ctx: ctx)
    }

    // 이름으로 준 항목을 ID로 바꾼다. 과목을 먼저 찾아야 과목 안의 항목을 그 과목에서 찾는다.
    static func resolved(_ json: JSONValue, _ fields: [FieldSpec], _ ctx: ActionContext) throws -> [String: JSONValue] {
        guard case .object(var o) = json else { throw CLIError(exit: .usage, message: String(localized: .runNotObject)) }
        let r = Resolver(ctx)
        var course: CourseRef?
        for f in fields.sorted(by: { ($0.ref == .course ? 0 : 1) < ($1.ref == .course ? 0 : 1) }) {
            if f.role == .new {
                if o[f.name] == nil { o[f.name] = .string(UUID().uuidString) }
                continue
            }
            guard let kind = f.ref, let v = o[f.name] else { continue }
            o[f.name] = try strings(v) { s in
                if kind == .course {
                    let c = try r.course(s)
                    course = course ?? c
                    return c.id.uuidString
                }
                if kind.byPath { return try r.path(kind, s, in: course) }
                return UUID(uuidString: s) != nil ? s : try r.id(kind, s, in: course).uuidString
            }
        }
        return o
    }

    static func strings(_ v: JSONValue, _ f: (String) throws -> String) throws -> JSONValue {
        switch v {
        case .string(let s): .string(try f(s))
        case .array(let items): .array(try items.map { try strings($0, f) })
        default: v
        }
    }

    static func describe(_ e: DecodingError) -> String { e.summary }
}
