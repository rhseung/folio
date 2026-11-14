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
        guard let type = Actions.all.first(where: { $0.command == name }) else {
            throw CLIError(
                exit: .usage, message: String(localized: .runUnknownAction(name)),
                candidates: Actions.all.map { $0.command }.filter { $0.hasPrefix(action.first ?? "") })
        }
        let text = input == "-" ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) : input
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else {
            throw CLIError(exit: .usage, message: String(localized: .runNotJson))
        }
        try execute(type, json, try CLI.context(g))
    }

    func execute<A: Action>(_ type: A.Type, _ json: JSONValue, _ ctx: ActionContext) throws {
        guard case .object(var o) = json else { throw CLIError(exit: .usage, message: String(localized: .runNotObject)) }
        let r = Resolver(ctx)
        var course: CourseRef?
        for f in A.spec.fields.sorted(by: { ($0.ref == .course ? 0 : 1) < ($1.ref == .course ? 0 : 1) }) {
            if f.role == .new {
                if o[f.name] == nil { o[f.name] = .string(UUID().uuidString) }
                continue
            }
            guard let kind = f.ref, let v = o[f.name] else { continue }
            o[f.name] = try Self.strings(v) { s in
                if kind == .course {
                    let c = try r.course(s)
                    course = course ?? c
                    return c.id.uuidString
                }
                if kind.byPath { return try r.path(kind, s, in: course) }
                return UUID(uuidString: s) != nil ? s : try r.id(kind, s, in: course).uuidString
            }
        }

        if let (key, current) = try A.currentFile(ctx), let given = o[key] { o[key] = current.overlaid(with: given) }
        try perform(spec: try A.decode(JSONEncoder().encode(JSONValue.object(o))), g, ctx: ctx)
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
