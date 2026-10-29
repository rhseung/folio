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
    // Unrecognized words stay in the name, so `exam scope --taught` names its action.
    @Argument(parsing: .allUnrecognized, help: ArgumentHelp(String(localized: .runHelpAction), valueName: "action")) var action: [String]
    @Option(help: ArgumentHelp(String(localized: .runHelpInput), valueName: "JSON")) var input: String

    func run() throws {
        let name = action.joined(separator: " ")
        guard let type = Actions.all.first(where: { $0.command == name }) else {
            throw CLIError(exit: .usage, message: String(localized: .runUnknownAction(name)), candidates: Actions.all.map { $0.command }.filter { $0.hasPrefix(action.first ?? "") })
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
        case .keyNotFound(let key, let c): String(localized: .runDecodeKeyNotFound(([path(c)] + [key.stringValue]).filter { !$0.isEmpty }.joined(separator: ".")))
        case .typeMismatch(let t, let c): String(localized: .runDecodeTypeMismatch(path(c), "\(t)"))
        case .valueNotFound(let t, let c): String(localized: .runDecodeValueNotFound(path(c), "\(t)"))
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
            throw CLIError(exit: .usage, message: String(localized: .runBadInput(RunCommand.describe(error))), hints: [String(localized: .runBadInputHint)])
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
