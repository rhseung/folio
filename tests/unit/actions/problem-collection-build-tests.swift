import FolioActions
import FolioCore
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct ProblemCollectionBuildTests {
    static let course = ActionTests.graphTheory
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore
    let set = UUID()

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
        try run(MaterialTrack(course: Self.course, assignments: false))
        try run(
            ProblemSetAdd(
                id: set, course: Self.course, title: "Exercise 1",
                problems: [Problem(number: "1", text: "Prove it."), Problem(number: "2", text: "Find $x$.", format: .short, answer: "3")]))
    }

    @discardableResult
    func run(_ action: some Action, dryRun: Bool = false) throws -> ActionContext {
        let ctx = ActionContext(gist: gist, device: device, now: now, dryRun: dryRun)
        try action.run(ctx)
        return ctx
    }

    var store: CourseStore { get throws { try ActionContext(gist: gist, device: device).store(Self.course) } }
    func file() throws -> CourseFile { try ActionContext(gist: gist, device: device).file(Self.course) }

    var files: ProblemCollectionFiles {
        get throws { ProblemCollectionFiles(store: try store, file: try file(), semester: nil, author: "") }
    }

    // 앱이 화면 밖에서 빌드해 둔 PDF다. 빌드 출력 폴더 밖의 파일은 액션이 받지 않는다.
    func built(_ text: String, of tex: URL) throws -> String {
        let folder = TexEngine.outputFolder(for: tex)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(UUID().uuidString).pdf")
        try Data(text.utf8).write(to: url)
        return url.path
    }

    func build(_ tag: String, overwrite: Bool = false, problems: [UUID] = []) throws -> ActionContext {
        let f = try files
        return try run(
            ProblemCollectionBuild(
                course: Self.course, problems: problems, pdf: try built("%PDF \(tag)", of: f.problemsTeX),
                solutionsPDF: try built("%PDF \(tag) solutions", of: f.solutionsTeX), overwrite: overwrite))
    }

    @Test func bothPDFsGoToStudyAsMaterialsThatKnowTheyWereBuilt() throws {
        let f = try files
        #expect(f.problemsPath == "Study/EC4207-Practice-Problems.pdf" && f.solutionsPath == "Study/EC4207-Practice-Solutions.pdf")
        let ctx = try build("first")
        #expect(ctx.changes.prefix(2).map(\.kind) == [.added, .added])
        #expect(try store.readText(f.problemsPath) == "%PDF first")
        #expect(try store.readText(f.solutionsPath) == "%PDF first solutions")
        let materials = try file().materials
        let problems = try #require(materials.first { $0.path == f.problemsPath })
        let solutions = try #require(materials.first { $0.path == f.solutionsPath })
        #expect(problems.builtHash == problems.hash && solutions.builtHash == solutions.hash)
        #expect(solutions.solutionOf == problems.id)

        // 이 액션이 만든 PDF는 묻지 않고 바꾼다.
        try build("again")
        #expect(try store.readText(f.problemsPath) == "%PDF again")
    }

    // 같은 이름의 PDF가 손으로 만든 문제집이면 덮어쓰지 않는다.
    @Test func aCollectionMadeElsewhereIsNotOverwritten() throws {
        let f = try files
        try build("first")
        try store.writeText(f.problemsPath, text: "%PDF by hand")
        #expect(throws: ActionError.self) { try build("second") }
        #expect(try store.readText(f.problemsPath) == "%PDF by hand")
        try build("third", overwrite: true)
        #expect(try store.readText(f.problemsPath) == "%PDF third")
    }

    @Test func aDryRunWritesNothing() throws {
        let f = try files
        let ctx = try run(ProblemCollectionBuild(course: Self.course), dryRun: true)
        #expect(ctx.changes.map(\.kind) == [.added, .added])
        #expect(!FileManager.default.fileExists(atPath: try store.fileURL(f.problemsPath).path))
    }

    @Test func nothingPickedIsRefused() throws {
        #expect(throws: ActionError.self) { try build("none", problems: [UUID()]) }
    }

    // 빌드 출력 폴더 밖의 파일로 과목 PDF를 바꾸지 못한다.
    @Test func aPDFFromElsewhereIsRefused() throws {
        let elsewhere = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        try Data("%PDF".utf8).write(to: elsewhere)
        #expect(throws: ActionError.self) {
            try run(ProblemCollectionBuild(course: Self.course, pdf: elsewhere.path, solutionsPDF: elsewhere.path))
        }
    }

    // 고른 문제만 넣는다. 표지의 이름은 설정에서 읽는다.
    @Test func theCollectionHoldsThePickedProblemsAndTheCoverName() throws {
        let picked = try #require(try file().problemSets.first { $0.id == set }?.problems.last)
        let f = ProblemCollectionFiles(store: try store, file: try file(), semester: nil, author: "Kim", problems: [picked.id])
        #expect(f.collection.problemCount == 1 && f.collection.author == "Kim")
        #expect(f.collection.course.hasPrefix("EC4207 "))
        #expect(f.collection.problemsTeX.contains("\\prob[half]{Exercise 1}{2}{}"))
    }
}
