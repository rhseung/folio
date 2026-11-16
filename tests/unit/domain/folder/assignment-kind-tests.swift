import Foundation
import Testing

@testable import FolioDomain

// 자료 추측, 정리 계획, 빠른 추가, 과제 폴더 이름이 `settings.json`의 과제 종류 표 하나를 읽는지 본다.
struct AssignmentKindTests {
    static let practice = AssignmentKind(prefix: "PS", aliases: ["problem set", "연습 과제"])
    static let table = AssignmentKind.builtIn + [practice]
    static let settings = Settings(assignmentKinds: table)

    @Test func settingsFallBackToTheBuiltInTable() throws {
        #expect(Settings().assignmentKindTable == AssignmentKind.builtIn)
        let read = try JSONDecoder().decode(Settings.self, from: Data(#"{"assignmentKinds":[{"prefix":"PS"}]}"#.utf8))
        #expect(read.assignmentKindTable == [AssignmentKind(prefix: "PS")])
        #expect(read.assignmentKindTable.first?.aliases == [])
    }

    @Test func folderNamesAndTitlesReadTheTable() {
        let a = Assignment(device: UUID(), at: .distantPast, title: "PS 3")
        #expect(AssignmentFiles.folder(of: a) == "PS 3")
        #expect(AssignmentFiles.folder(of: a, kinds: Self.table) == "PS03")
        #expect(StandardLayout.assignmentFolder("PS03") == nil)
        #expect(StandardLayout.assignmentFolder("PS03", kinds: Self.table)?.prefix == "PS")
        #expect(AssignmentFiles.guessKind(fileName: "PS3_류현승.pdf", kinds: Self.table) == .submission)
        #expect(AssignmentKind.unmatchedFolders(["PS03", "HW01"], assignments: [a], kinds: Self.table) == ["HW01"])
    }

    // 이미 있는 과제 제목과 폴더는 기본 표에서 그대로 읽힌다.
    @Test func builtInTitlesKeepTheirFolders() {
        let titles = ["HW5", "hw 5", "Lab3 report", "SP1", "Report 2", "Project1", "Reading 4", "Slow Problem 2", "기말 프로젝트"]
        let folders = titles.map { AssignmentFiles.folder(of: Assignment(device: UUID(), at: .distantPast, title: $0)) }
        #expect(folders == ["HW05", "HW05", "Lab03", "SP01", "Report02", "Project01", "Reading04", "Slow Problem 2", "기말 프로젝트"])
    }

    @Test func quickAddReadsTheTable() {
        let line = "PS3 금"
        #expect(QuickAdd.parse(line, courses: [], now: .distantPast, calendar: .current).folderName == nil)
        #expect(QuickAdd.parse(line, courses: [], settings: Self.settings, now: .distantPast, calendar: .current).folderName == "PS03")
    }

    @Test func intakeReadsAliasesFromTheTable() {
        let places = ["Assignments/PS02", "Assignments/HW02"]
        func guess(_ settings: Settings) -> String {
            MaterialIntake.guess(
                IncomingFile(name: "problem set 2.pdf"), places: places, sessions: [], now: .distantPast, settings: settings,
                calendar: .current
            ).folder
        }
        #expect(guess(Settings()) != "Assignments/PS02")
        #expect(guess(Self.settings) == "Assignments/PS02")
    }

    @Test func cleanupReadsAliasesFromTheTable() {
        let files = [FolderTree(name: "problem set 4.pdf", content: .file(size: 1))]
        let course = FolderTree(name: "EC4207 그래프 이론", content: .folder([FolderTree(name: "숙제", content: .folder(files))]))
        var builtIn = CoursePlanner(course: course)
        var custom = CoursePlanner(course: course, kinds: Self.table)
        #expect(builtIn.plan().map(\.to) == ["Assignments/HW00/problem set 4.pdf"])
        #expect(custom.plan().map(\.to) == ["Assignments/HW04/problem set 4.pdf"])
    }

    @Test func badPrefixesBreakTheSettingsRule() {
        func broken(_ kinds: [AssignmentKind]) -> Bool {
            Settings.model.violations(in: Settings(assignmentKinds: kinds)).contains { $0.rule.name == "Settings.assignmentKinds" }
        }
        #expect(!broken(Self.table))
        #expect(broken([]))
        #expect(broken([AssignmentKind(prefix: "HW 2")]))
        #expect(broken([AssignmentKind(prefix: "과제")]))
        #expect(broken([AssignmentKind(prefix: "HW"), AssignmentKind(prefix: "HW", aliases: ["숙제"])]))
    }
}
