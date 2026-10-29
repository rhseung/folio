import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import", abstract: "노션, 캘린더, 단원 표 같은 일회성 가져오기",
        discussion: """
            가져올 파일은 실제 학업 데이터라 저장소에 넣지 않는다. 먼저 --dry-run으로 계획을 보고, 확인한 뒤 실행한다.
            """,
        subcommands: [Notion.self, Notes.self, Calendar.self, Exams.self, Units.self, Requirements.self, Handbook.self])

    static func url(_ path: String) -> URL { URL(filePath: (path as NSString).expandingTildeInPath) }

    static func read<T: Decodable>(_ type: T.Type, _ path: String, iso8601: Bool = false) throws -> T {
        let decoder = JSONDecoder()
        if iso8601 { decoder.dateDecodingStrategy = .iso8601 }
        do {
            return try decoder.decode(T.self, from: Data(contentsOf: url(path)))
        } catch let e as DecodingError {
            throw CLIError(exit: .usage, message: "\(path)의 형식이 맞지 않습니다: \(RunCommand.describe(e))")
        } catch {
            throw CLIError(exit: .usage, message: "\(path)을(를) 읽지 못했습니다")
        }
    }

    struct Notion: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "노션 학기, 강의, 성적을 transcript.json, catalog.json, course.json으로", discussion: """
            export.json은 Notion MCP로 읽은 내용을 NotionExport 형식으로 담은 파일이다. transcript.json이나 catalog.json이
            이미 있으면 실행하지 않고(종료 코드 4), course.json이 있는 과목 폴더는 건너뛴다. 학기별 GPA를 노션 값과 비교한다.

            예시:
              folio import notion ~/Downloads/export.json --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("NotionExport JSON", valueName: "export.json"), completion: .file(extensions: ["json"])) var file: String

        func run() throws {
            try perform(spec: ImportNotion(export: try read(NotionExport.self, file)), g, ctx: try CLI.context(g))
        }
    }

    struct Notes: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "노션 강의 정리와 점수를 노트, 회차, 성적 항목으로", discussion: """
            덤프 폴더는 과목마다 <노션 페이지 ID>/index.json, notes/, assets/를 가진다. 노트 ID가 노션 페이지 ID라서 다시
            실행해도 중복되지 않고, 기존 항목에는 덧붙이기만 한다.

            예시:
              folio import notes ~/Downloads/notion-dump --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("덤프 폴더", valueName: "folder"), completion: .directory) var folder: String

        func run() throws {
            try perform(spec: ImportNotes(folder: url(folder).path), g, ctx: try CLI.context(g))
        }
    }

    struct Calendar: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "캘린더의 수업을 회차로", discussion: """
            meetings.json은 CalendarMeeting 목록이다. 이미 있는 회차는 빈 시각과 주제만 채우고, 범위 안에서 수업이 없는 날의
            회차는 휴강으로 표시하며, 회차 이름의 복습 노트를 연결한다. lab 번호가 있는 수업은 그 실험의 단원(없으면
            Lab<번호> <주제>로 만든다)에 연결한다.

            예시:
              folio import calendar ~/Downloads/meetings.json --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("CalendarMeeting 목록 JSON", valueName: "meetings.json"), completion: .file(extensions: ["json"])) var file: String

        func run() throws {
            try perform(spec: ImportCalendar(meetings: try read([CalendarMeeting].self, file, iso8601: true)), g, ctx: try CLI.context(g))
        }
    }

    struct Exams: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "캘린더의 시험을 시험으로", discussion: """
            exams.json은 구글 캘린더 "시험" 캘린더에서 읽은 CalendarExam 목록이다. 같은 날 시험은 빈 칸만 채우고, 다른 날이면
            바꾸지 않고 알린다.

            예시:
              folio import exams ~/Downloads/exams.json --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("CalendarExam 목록 JSON", valueName: "exams.json"), completion: .file(extensions: ["json"])) var file: String

        func run() throws {
            try perform(spec: ImportExams(exams: try read([CalendarExam].self, file, iso8601: true)), g, ctx: try CLI.context(g))
        }
    }

    struct Units: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "단원 표를 단원으로", discussion: """
            파일마다 {"course": <과목 폴더 이름>, "units": [{"title", "sessions": ["3주차-1"], "children"}]}. 제목으로 맞춰
            없는 단원만 더하고, 회차 연결은 더하기만 한다.

            예시:
              folio import units ~/Downloads/EC4207-units.json --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("단원 JSON. 여러 개", valueName: "units.json"), completion: .file(extensions: ["json"])) var files: [String]

        func run() throws {
            try perform(spec: ImportUnits(files: try files.map { try read(UnitFile.self, $0) }), g, ctx: try CLI.context(g))
        }
    }

    struct Requirements: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "졸업 요건 분류와 학생 정보", discussion: """
            강의 코드 표에 없는 코드가 있으면 실행하지 않는다(종료 코드 4).

            예시:
              folio import requirements ~/Downloads/requirements.json --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("RequirementFile JSON", valueName: "requirements.json"), completion: .file(extensions: ["json"])) var file: String

        func run() throws {
            try perform(spec: ImportRequirements(file: try read(RequirementFile.self, file)), g, ctx: try CLI.context(g))
        }
    }

    struct Handbook: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "학사편람 분류 표", discussion: """
            같은 해 표는 바꾼다. 과목의 분류 제안을 보여 주며, 앱의 졸업 요건 화면에서 승인하거나 --accept로 바로 적용한다.

            예시:
              folio import handbook ~/Downloads/handbook-2023.json --dry-run
              folio import handbook ~/Downloads/handbook-2023.json --accept
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("Handbook JSON", valueName: "handbook.json"), completion: .file(extensions: ["json"])) var file: String
        @Flag(help: "분류 제안을 과목에 바로 적용") var accept = false

        func run() throws {
            try perform(spec: ImportHandbook(handbook: try read(FolioDomain.Handbook.self, file), accept: accept), g, ctx: try CLI.context(g))
        }
    }
}
