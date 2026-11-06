import ArgumentParser
import CryptoKit
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Resolver {
    func notePath(_ ref: String) throws -> (CourseRef, NoteFile, String) {
        let (c, name) = try split(ref)
        let n = try note(name, in: c)
        return (c, n, c.store.coursePath(of: n.url) ?? name)
    }
}

/// What `note show --json` reports and `note write --expect` checks: the note as it was read.
func contentHash(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

func readText(_ source: String) throws -> String {
    if source == "-" { return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) }
    do {
        return try String(contentsOf: URL(filePath: absolute(source)), encoding: .utf8)
    } catch {
        throw CLIError(exit: .usage, message: String(localized: .noteReadFailed(source)))
    }
}

struct NoteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note", abstract: String(localized: .noteAbstract),
        subcommands: [List.self, Show.self, Add.self, Write.self, Edit.self, Link.self, Migrate.self, Retitle.self] + GeneratedCommands.note)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteListAbstract), discussion: String(localized: .noteListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        struct Item: Encodable {
            var id: UUID?
            var path: String
            var kind: NoteKind
            /// The first of `sessionIds`, kept for readers from before a review note could cover several.
            var sessionId: UUID?
            var sessionIds: [UUID]
            var examId: UUID?
            var unitIds: [UUID]
        }

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let store = c.store
            let notes = try store.notes()
            let path = { (n: NoteFile) in store.coursePath(of: n.url) ?? n.url.lastPathComponent }
            if g.json {
                return try printJSON(notes.map { Item(id: $0.meta.id, path: path($0), kind: $0.meta.kind, sessionId: $0.meta.sessionId, sessionIds: $0.meta.sessionIds, examId: $0.meta.examId, unitIds: $0.meta.unitIds) })
            }
            let f = c.file
            let session = { (n: NoteFile) in f.sessionSpan(of: n.meta.id) ?? "" }
            if lines {
                for n in notes { line(["\(c.code)/\(path(n))", n.title, n.meta.kind.rawValue, session(n)]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: [String(localized: .noteListHeaderNote), String(localized: .noteListHeaderKind), String(localized: .noteListHeaderSession), String(localized: .noteListHeaderPath)], shrink: [3])
            for n in notes { t.rows.append([n.title, n.meta.kind.rawValue, session(n), path(n)]) }
            t.print()
            footer(notes.count)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteShowAbstract), discussion: String(localized: .noteShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .noteShowHelpNote), valueName: "note"), completion: Complete.notes) var note: String = ""

        struct Body: Encodable {
            var id: UUID?
            var path: String
            var text: String
            /// Pass to `note write --expect` so a change made meanwhile isn't overwritten.
            var hash: String
        }

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, n, path) = try r.notePath(note)
            let text = try c.store.read(n)
            if g.json { return try printJSON(Body(id: n.meta.id, path: path, text: text, hash: contentHash(text))) }
            say(text)
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteAddAbstract), discussion: String(localized: .noteAddDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String
        @Argument(help: ArgumentHelp(String(localized: .noteAddHelpTitle), valueName: "title")) var title: String
        @Option(help: ArgumentHelp(String(localized: .commonHelpKind))) var kind: NoteKind = .free
        @Option(help: ArgumentHelp(String(localized: .noteAddHelpFormat))) var format: NoteFormat = .markdown
        @Option(help: ArgumentHelp(String(localized: .noteAddHelpBody), valueName: "file"), completion: .file()) var body: String?
        @Option(help: ArgumentHelp(String(localized: .noteLinkHelpSession), valueName: "session"), completion: Complete.sessions) var session: String?
        @Option(help: ArgumentHelp(String(localized: .noteLinkHelpExam), valueName: "exam"), completion: Complete.exams) var exam: String?
        @Option(help: ArgumentHelp(String(localized: .noteLinkHelpUnit), valueName: "unit"), completion: Complete.units) var unit: [String] = []
        @Option(help: .hidden) var id: UUID?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            try perform(spec: NoteAdd(id: id ?? UUID(), course: c.id, title: title, kind: kind, format: format, body: try body.map(readText),
                                      session: try session.map { try r.session(c.local($0), in: c).id }, exam: try exam.map { try r.exam(c.local($0), in: c).id },
                                      units: try unit.map { try r.unit(c.local($0), in: c).id }),
                        g, ctx: ctx)
        }
    }

    struct Migrate: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteMigrateAbstract), discussion: String(localized: .noteMigrateDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .noteMigrateHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let id = try course.map { try Resolver(ctx).course($0).id }
            try perform(spec: NoteMigrate(course: id), g, ctx: ctx)
        }
    }

    struct Retitle: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteRetitleAbstract), discussion: String(localized: .noteRetitleDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .noteRetitleHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let id = try course.map { try Resolver(ctx).course($0).id }
            let result = try perform(spec: NoteRetitleSessions(course: id), g, ctx: ctx)
            if !g.json, let batch = result.made { say(String(localized: .noteRetitleUndo(batch.uuidString)).styled(.dim)) }
        }
    }

    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteWriteAbstract), discussion: String(localized: .noteWriteDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpNote), valueName: "note"), completion: Complete.notes) var note: String = ""
        @Option(help: ArgumentHelp(String(localized: .noteWriteHelpFile), valueName: "file"), completion: .file()) var file: String
        @Option(help: ArgumentHelp(String(localized: .noteWriteHelpExpect), valueName: "hash")) var expect: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let (c, n, path) = try Resolver(ctx).notePath(note)
            var expected: String?
            if let expect {
                let current = try c.store.read(n)
                guard contentHash(current) == expect.lowercased() else {
                    throw CLIError(exit: .conflict, message: String(localized: .noteWriteConflict(path)),
                                   hints: [String(localized: .noteWriteConflictHint(c.code, path))])
                }
                // The action checks again right before writing, so a change between here and there is caught too.
                expected = current
            }
            try perform(spec: NoteWrite(course: c.id, note: path, text: try readText(file), expected: expected), g, ctx: ctx)
        }
    }

    struct Edit: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteEditAbstract), discussion: String(localized: .noteEditDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpNote), valueName: "note"), completion: Complete.notes) var note: String = ""
        @Option(help: ArgumentHelp(String(localized: .noteEditHelpOld), valueName: "text")) var old: [String] = []
        @Option(help: ArgumentHelp(String(localized: .noteEditHelpNew), valueName: "text")) var new: [String] = []
        @Option(help: ArgumentHelp(String(localized: .noteEditHelpAppend), valueName: "text")) var append: String?

        func run() throws {
            guard old.count == new.count else { throw CLIError(exit: .usage, message: String(localized: .noteEditUnpaired(old.count, new.count))) }
            let ctx = try CLI.context(g)
            let (c, _, path) = try Resolver(ctx).notePath(note)
            let replacements = zip(old, new).map { NoteEdit.Replacement(old: $0, new: $1) }
            try perform(spec: NoteEdit(course: c.id, note: path, replacements: replacements, append: append), g, ctx: ctx)
        }
    }

    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteLinkAbstract), discussion: String(localized: .noteLinkDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpNote), valueName: "note"), completion: Complete.notes) var note: String = ""
        @Option(help: ArgumentHelp(String(localized: .commonHelpKind))) var kind: NoteKind
        @Option(help: ArgumentHelp(String(localized: .noteLinkHelpSession), valueName: "session"), completion: Complete.sessions) var session: String?
        @Option(help: ArgumentHelp(String(localized: .noteLinkHelpExam), valueName: "exam"), completion: Complete.exams) var exam: String?
        @Option(help: ArgumentHelp(String(localized: .noteLinkHelpUnit), valueName: "unit"), completion: Complete.units) var unit: [String] = []
        @Option(help: ArgumentHelp(String(localized: .noteLinkHelpMath))) var math: MathSyntax?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(note)
            try perform(spec: NoteLink(course: c.id, note: try r.noteID(name, in: c), kind: kind, session: try session.map { try r.session(c.local($0), in: c).id },
                                 exam: try exam.map { try r.exam(c.local($0), in: c).id }, units: try unit.map { try r.unit(c.local($0), in: c).id }, math: math),
                        g, ctx: ctx)
        }
    }
}
