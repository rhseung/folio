import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import", abstract: String(localized: .importAbstract),
        discussion: String(localized: .importDiscussion),
        subcommands: [Notion.self, Notes.self, Calendar.self, Exams.self, Units.self, Requirements.self, Handbook.self])

    static func url(_ path: String) -> URL { URL(filePath: (path as NSString).expandingTildeInPath) }

    static func read<T: Decodable>(_ type: T.Type, _ path: String, iso8601: Bool = false) throws -> T {
        let decoder = JSONDecoder()
        if iso8601 { decoder.dateDecodingStrategy = .iso8601 }
        do {
            return try decoder.decode(T.self, from: Data(contentsOf: url(path)))
        } catch let e as DecodingError {
            throw CLIError(exit: .usage, message: String(localized: .importBadFormat(path, RunCommand.describe(e))))
        } catch {
            throw CLIError(exit: .usage, message: String(localized: .importUnreadable(path)))
        }
    }

    struct Notion: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .importNotionAbstract), discussion: String(localized: .importNotionDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("NotionExport JSON", valueName: "export.json"), completion: .file(extensions: ["json"])) var file: String

        func run() throws {
            try perform(spec: ImportNotion(export: try read(NotionExport.self, file)), g, ctx: try CLI.context(g))
        }
    }

    struct Notes: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .importNotesAbstract), discussion: String(localized: .importNotesDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .importNotesHelpFolder), valueName: "folder"), completion: .directory) var folder: String

        func run() throws {
            try perform(spec: ImportNotes(folder: url(folder).path), g, ctx: try CLI.context(g))
        }
    }

    struct Calendar: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .importCalendarAbstract), discussion: String(localized: .importCalendarDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .importCalendarHelpFile), valueName: "meetings.json"), completion: .file(extensions: ["json"])) var file: String

        func run() throws {
            try perform(spec: ImportCalendar(meetings: try read([CalendarMeeting].self, file, iso8601: true)), g, ctx: try CLI.context(g))
        }
    }

    struct Exams: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .importExamsAbstract), discussion: String(localized: .importExamsDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .importExamsHelpFile), valueName: "exams.json"), completion: .file(extensions: ["json"])) var file: String

        func run() throws {
            try perform(spec: ImportExams(exams: try read([CalendarExam].self, file, iso8601: true)), g, ctx: try CLI.context(g))
        }
    }

    struct Units: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .importUnitsAbstract), discussion: String(localized: .importUnitsDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .importUnitsHelpFiles), valueName: "units.json"), completion: .file(extensions: ["json"])) var files: [String]

        func run() throws {
            try perform(spec: ImportUnits(files: try files.map { try read(UnitFile.self, $0) }), g, ctx: try CLI.context(g))
        }
    }

    struct Requirements: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .importRequirementsAbstract), discussion: String(localized: .importRequirementsDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("RequirementFile JSON", valueName: "requirements.json"), completion: .file(extensions: ["json"])) var file: String

        func run() throws {
            try perform(spec: ImportRequirements(file: try read(RequirementFile.self, file)), g, ctx: try CLI.context(g))
        }
    }

    struct Handbook: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .importHandbookAbstract), discussion: String(localized: .importHandbookDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("Handbook JSON", valueName: "handbook.json"), completion: .file(extensions: ["json"])) var file: String
        @Flag(help: ArgumentHelp(String(localized: .importHandbookHelpAccept))) var accept = false

        func run() throws {
            try perform(spec: ImportHandbook(handbook: try read(FolioDomain.Handbook.self, file), accept: accept), g, ctx: try CLI.context(g))
        }
    }
}
