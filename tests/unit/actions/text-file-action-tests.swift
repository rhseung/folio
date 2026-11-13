import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import PDFKit
import Testing

struct TextFileActionTests {
    static let course = ActionTests.graphTheory
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore
    let store: CourseStore

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
        store = try ActionContext(gist: gist, device: device).store(Self.course)
        try run(MaterialTrack(course: Self.course))
    }

    @discardableResult
    func run(_ action: some Action, dryRun: Bool = false) throws -> ActionContext {
        let ctx = ActionContext(gist: gist, device: device, now: now, dryRun: dryRun)
        try action.run(ctx)
        return ctx
    }

    func material(_ path: String) throws -> Material {
        try #require(try ActionContext(gist: gist, device: device).file(Self.course).materials.first { $0.path == path })
    }

    static let tex = "Study/Problems.tex"

    @Test func writeReplacesTheFileAndItsHash() throws {
        let before = try material(Self.tex)

        // Same length as the fixture's text, so only the hash can tell the files apart.
        let text = String(try store.readText(Self.tex).reversed())
        try run(MaterialWrite(course: Self.course, material: before.id, text: text))
        #expect(try store.readText(Self.tex) == text)
        let after = try material(Self.tex)
        #expect(after.size == before.size)
        #expect(after.hash != before.hash)
    }

    @Test func aFileChangedElsewhereIsNotOverwritten() throws {
        let m = try material(Self.tex)
        let read = try store.readText(Self.tex)
        try store.writeText(Self.tex, text: read + "% 바깥에서 고침\n")
        #expect(throws: ActionError.conflict("자료가 다른 곳에서 바뀌었습니다: \(Self.tex)")) {
            try run(MaterialWrite(course: Self.course, material: m.id, text: "덮어쓰기", expected: read))
        }
        #expect(try store.readText(Self.tex).hasSuffix("바깥에서 고침\n"))
    }

    /// A CP949 `.csv` from Excel would come back as U+FFFD wherever it didn't decode as UTF-8.
    @Test func aFileThatIsNotUTF8IsLeftAsItIs() throws {
        let cp949 = Data([0xC7, 0xD1, 0xB1, 0xDB, 0x2C, 0x31, 0x0A])  // "한글,1\n"
        try cp949.write(to: store.fileURL("Exams/Midterm/scores.csv"))
        try run(MaterialTrack(course: Self.course))
        let m = try material("Exams/Midterm/scores.csv")
        #expect(throws: StorageError.notUTF8("Exams/Midterm/scores.csv")) { try store.readText(m.path) }
        #expect(throws: ActionError.rule("UTF-8 텍스트가 아니라서 Folio에서 고치지 않습니다: Exams/Midterm/scores.csv")) {
            try run(MaterialWrite(course: Self.course, material: m.id, text: "x"))
        }
        #expect(try Data(contentsOf: store.fileURL(m.path)) == cp949)
    }

    @Test func aPDFIsNotText() throws {
        let m = try material("Study/Problems.pdf")
        #expect(throws: ActionError.rule("텍스트 파일이 아니라서 쓸 수 없습니다: Study/Problems.pdf")) {
            try run(MaterialWrite(course: Self.course, material: m.id, text: "x"))
        }
    }

    @Test func dryRunWritesNothing() throws {
        let m = try material(Self.tex)
        let read = try store.readText(Self.tex)
        let ctx = try run(MaterialWrite(course: Self.course, material: m.id, text: "x"), dryRun: true)
        #expect(ctx.changes.map(\.kind) == [.changed])
        #expect(try store.readText(Self.tex) == read)
    }

    /// Where the app's build of `source` would leave its PDF; the action takes nothing from anywhere else.
    func builtPDF(_ text: String, of source: String = Self.tex) throws -> URL {
        let folder = TexEngine.outputFolder(for: store.fileURL(source))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(UUID().uuidString).pdf")
        try Data(text.utf8).write(to: url)
        return url
    }

    /// The fixture's Problems.pdf came with the course, so the first build asks; after that the PDF is the build's own
    /// until something else replaces it.
    @Test func buildReplacesOnlyItsOwnPDFWithoutAsking() throws {
        let tex = try material(Self.tex)
        let given = try store.readText("Study/Problems.pdf")
        #expect(throws: ActionError.self) {
            try run(MaterialBuild(course: Self.course, material: tex.id, pdf: try builtPDF("%PDF-1.7 built").path))
        }
        #expect(try store.readText("Study/Problems.pdf") == given)

        let ctx = try run(MaterialBuild(course: Self.course, material: tex.id, pdf: try builtPDF("%PDF-1.7 built").path, overwrite: true))
        #expect(ctx.changes.first == Change(.changed, "2026-3/EC4207 그래프 이론/Study/Problems.pdf"))
        #expect(try store.readText("Study/Problems.pdf") == "%PDF-1.7 built")
        let pdf = try material("Study/Problems.pdf")
        #expect(try material(Self.tex).sourceOf == pdf.id && pdf.builtHash == pdf.hash)

        try run(MaterialBuild(course: Self.course, material: tex.id, pdf: try builtPDF("%PDF-1.7 again").path))
        #expect(try store.readText("Study/Problems.pdf") == "%PDF-1.7 again")

        try store.writeText("Study/Problems.pdf", text: "%PDF from elsewhere")
        #expect(throws: ActionError.self) { try run(MaterialBuild(course: Self.course, material: tex.id, pdf: try builtPDF("%PDF").path)) }
    }

    @Test func buildAddsAPDFThatWasNotThere() throws {
        try store.writeText("Assignments/HW03/hw.tex", text: "\\documentclass{article}\n")
        try run(MaterialTrack(course: Self.course))
        let tex = try material("Assignments/HW03/hw.tex")
        let ctx = try run(MaterialBuild(course: Self.course, material: tex.id, pdf: try builtPDF("%PDF", of: tex.path).path))
        #expect(ctx.changes.first == Change(.added, "2026-3/EC4207 그래프 이론/Assignments/HW03/hw.pdf"))
        #expect(try material("Assignments/HW03/hw.tex").sourceOf == material("Assignments/HW03/hw.pdf").id)
    }

    /// A move keeps the ids and their links, so the old link would send the build back to the old folder.
    @Test func aMovedTexBuildsBesideItsNewPlace() throws {
        let tex = try material(Self.tex)
        try run(MaterialMove(course: Self.course, material: tex.id, to: "Assignments/HW03/hw.tex"))
        try run(MaterialBuild(course: Self.course, material: tex.id, pdf: try builtPDF("%PDF moved", of: "Assignments/HW03/hw.tex").path))
        #expect(try store.readText("Assignments/HW03/hw.pdf") == "%PDF moved")
        #expect(try store.readText("Study/Problems.pdf") != "%PDF moved")
        #expect(try material("Assignments/HW03/hw.tex").sourceOf == material("Assignments/HW03/hw.pdf").id)
    }

    /// Any other file would take the course PDF's place and be marked as built, so the next build wouldn't ask.
    @Test func aPDFFromOutsideTheBuildFolderIsRefused() throws {
        let tex = try material(Self.tex)
        let given = try store.readText("Study/Problems.pdf")
        let elsewhere = FileManager.default.temporaryDirectory.appending(path: "folio-\(UUID().uuidString).pdf")
        try Data("%PDF other".utf8).write(to: elsewhere)
        for path in [elsewhere.path, TexEngine.outputFolder(for: store.fileURL(Self.tex)).path + "/../x.pdf"] {
            #expect(throws: ActionError.rule("이 자료를 빌드한 결과가 아니라서 쓰지 않습니다: \(path)")) {
                try run(MaterialBuild(course: Self.course, material: tex.id, pdf: path, overwrite: true))
            }
        }
        #expect(try store.readText("Study/Problems.pdf") == given)
    }

    @Test func buildTakesOnlyTex() throws {
        let m = try material("Study/Problems.pdf")
        #expect(throws: ActionError.rule("LaTeX 파일(.tex)만 PDF로 만듭니다: Study/Problems.pdf")) {
            try run(MaterialBuild(course: Self.course, material: m.id))
        }
    }

    @Test
    func buildRunsTectonic() throws {
        try store.writeText("Assignments/HW03/hw.tex", text: "\\documentclass{article}\n\\begin{document}\nHello\n\\end{document}\n")
        try run(MaterialTrack(course: Self.course))
        try run(MaterialBuild(course: Self.course, material: try material("Assignments/HW03/hw.tex").id))
        let pdf = try Data(contentsOf: store.fileURL("Assignments/HW03/hw.pdf"))
        #expect(pdf.starts(with: Data("%PDF".utf8)))
    }

    @Test
    func aBrokenDocumentNamesItsLine() throws {
        try store.writeText("Assignments/HW03/hw.tex", text: "\\documentclass{article}\n\\begin{document}\n\\foo\n\\end{document}\n")
        try run(MaterialTrack(course: Self.course))
        let tex = try material("Assignments/HW03/hw.tex")
        #expect(throws: ActionError.rule("PDF를 만들지 못했습니다.\nhw.tex:3: Undefined control sequence")) {
            try run(MaterialBuild(course: Self.course, material: tex.id))
        }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL("Assignments/HW03/hw.pdf").path))
    }

    /// One build lists every mistake, and the PDF Tectonic still writes past them is not placed.
    @Test
    func aBrokenDocumentNamesEveryError() throws {
        try store.writeText(
            "Assignments/HW03/hw.tex", text: "\\documentclass{article}\n\\begin{document}\n\\foo\n\nA \\qux.\n\n\\baz\n\\end{document}\n")
        try run(MaterialTrack(course: Self.course))
        let tex = try material("Assignments/HW03/hw.tex")
        #expect(
            throws: ActionError.rule(
                "PDF를 만들지 못했습니다.\nhw.tex:3: Undefined control sequence\nhw.tex:5: Undefined control sequence\nhw.tex:7: Undefined control sequence"
            )
        ) {
            try run(MaterialBuild(course: Self.course, material: tex.id))
        }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL("Assignments/HW03/hw.pdf").path))
    }

    /// The PDF carries the day it was built: the same day gives the same bytes, the next day a new `\today`, and the PDF
    /// built the day before is still known as Folio's, so replacing it doesn't ask.
    @Test
    func aBuildIsStampedWithItsDay() throws {
        var seoul = Calendar(identifier: .gregorian)
        seoul.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        func build(day: Int, _ hour: Int, _ minute: Int) throws -> Data {
            let at = try #require(seoul.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)))
            let ctx = ActionContext(gist: gist, device: device, now: at, calendar: seoul)
            try MaterialBuild(course: Self.course, material: try material("Assignments/HW03/hw.tex").id).run(ctx)
            return try Data(contentsOf: store.fileURL("Assignments/HW03/hw.pdf"))
        }
        try store.writeText("Assignments/HW03/hw.tex", text: "\\documentclass{article}\n\\begin{document}\n\\today\n\\end{document}\n")
        try run(MaterialTrack(course: Self.course))
        let first = try build(day: 5, 0, 0)
        let lastMinute = try build(day: 5, 23, 59)
        let nextDay = try build(day: 6, 0, 0)
        #expect(first == lastMinute)
        #expect(nextDay != lastMinute)
        #expect(PDFDocument(data: nextDay)?.string?.contains("November 6, 2026") == true)
    }

    /// The SyncTeX data stays in the build folder, and a click on the placed PDF finds the line that wrote there.
    @Test
    func aBuildKeepsSyncTeXOutOfTheCourseFolder() throws {
        try store.writeText("Assignments/HW03/hw.tex", text: "\\documentclass{article}\n\\begin{document}\nHello world.\n\\end{document}\n")
        try run(MaterialTrack(course: Self.course))
        try run(MaterialBuild(course: Self.course, material: try material("Assignments/HW03/hw.tex").id))
        let source = store.fileURL("Assignments/HW03/hw.tex")
        #expect(FileManager.default.fileExists(atPath: TexEngine.synctex(for: source).path))
        let beside = try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path)
        #expect(!beside.contains { $0.contains("synctex") })
        let sync = try #require(TexEngine.syncTeX(for: source, showing: store.fileURL("Assignments/HW03/hw.pdf")))
        let place = try #require(sync.place(page: 1, x: 200, y: 132))
        #expect(URL(filePath: place.file).resolvingSymlinksInPath() == source.resolvingSymlinksInPath())
        #expect(place.line == 3)

        // Another PDF on screen, say one built on another device, is not what this data describes.
        try Data("%PDF-other".utf8).write(to: store.fileURL("Assignments/HW03/hw.pdf"))
        #expect(TexEngine.syncTeX(for: source, showing: store.fileURL("Assignments/HW03/hw.pdf")) == nil)
    }
}

struct MaterialNewTests {
    static let course = ActionTests.graphTheory
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore
    let store: CourseStore

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
        store = try ActionContext(gist: gist, device: device).store(Self.course)
        try run(MaterialTrack(course: Self.course))
    }

    @discardableResult
    func run(_ action: some Action, dryRun: Bool = false) throws -> ActionContext {
        let ctx = ActionContext(gist: gist, device: device, now: now, dryRun: dryRun)
        try action.run(ctx)
        return ctx
    }

    func file() throws -> CourseFile { try ActionContext(gist: gist, device: device).file(Self.course) }

    @Test func makesATrackedTexInTheAssignmentFolder() throws {
        let ctx = try run(MaterialNew(course: Self.course, folder: "Assignments/HW03", name: "hw3.tex"))
        #expect(try store.readText("Assignments/HW03/hw3.tex") == NewMaterialFile.text(for: "hw3.tex"))
        let m = try #require(try file().materials.first { $0.path == "Assignments/HW03/hw3.tex" })
        #expect(ctx.made == m.id)
        #expect(m.status == .classified && m.hash != nil)
        let hw = try #require(try file().assignments.first { $0.title == "HW03" })
        #expect(AssignmentFiles.materials(of: hw, in: try file().materials).contains { $0.id == m.id })
    }

    /// An exam's folder is made by its first file.
    @Test func makesTheFolderOfAnExamWithoutFiles() throws {
        try run(ExamAdd(course: Self.course, title: "기말고사"))
        try run(MaterialNew(course: Self.course, folder: "Exams/기말고사", name: "풀이.py"))
        #expect(try store.readText("Exams/기말고사/풀이.py") == "")
        #expect(try file().materials.contains { $0.path == "Exams/기말고사/풀이.py" })
    }

    @Test func aTakenNameIsRefusedAndLeftAsItIs() throws {
        try store.writeText("Study/a.txt", text: "원래")
        #expect(throws: ActionError.conflict("같은 이름의 파일이 이미 있습니다: Study/a.txt")) {
            try run(MaterialNew(course: Self.course, folder: "Study", name: "a.txt"))
        }
        #expect(try store.readText("Study/a.txt") == "원래")
        #expect(!FileManager.default.fileExists(atPath: store.fileURL("Study/a 2.txt").path))
    }

    @Test func receivedFoldersAndOtherFormatsAreRefused() throws {
        #expect(throws: ActionError.rule("새 파일은 과제·시험 폴더나 Study, Archive에만 만듭니다: Lectures")) {
            try run(MaterialNew(course: Self.course, folder: "Lectures", name: "a.tex"))
        }
        #expect(throws: ActionError.rule("Folio에서 편집하는 형식(.tex, 코드, .txt 등)만 만듭니다: a.pdf")) {
            try run(MaterialNew(course: Self.course, folder: "Study", name: "a.pdf"))
        }
        #expect(throws: ActionError.rule("파일 이름으로 쓸 수 없습니다: ../a.tex")) {
            try run(MaterialNew(course: Self.course, folder: "Study", name: "../a.tex"))
        }
    }

    @Test func aFolderNoExamOwnsIsRefused() throws {
        #expect(throws: ActionError.rule("과제나 시험의 폴더가 아닙니다: Exams/중간고사오타")) {
            try run(MaterialNew(course: Self.course, folder: "Exams/중간고사오타", name: "a.tex"))
        }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL("Exams/중간고사오타").path))
    }

    /// Its files were tracked one by one before `git init`; tracking now reads the folder as one project.
    @Test func aFolderThatBecameACodeProjectIsRefused() throws {
        try FileManager.default.createDirectory(at: store.fileURL("Assignments/HW03/.git"), withIntermediateDirectories: true)
        #expect(throws: ActionError.rule("코드 프로젝트 폴더 안에는 만들지 않습니다: Assignments/HW03")) {
            try run(MaterialNew(course: Self.course, folder: "Assignments/HW03", name: "hw3.tex"))
        }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL("Assignments/HW03/hw3.tex").path))
    }

    @Test func aDryRunWritesNothing() throws {
        let ctx = try run(MaterialNew(course: Self.course, folder: "Study", name: "b.tex"), dryRun: true)
        #expect(ctx.changes.contains { $0.kind == .added && $0.path.hasSuffix("Study/b.tex") })
        #expect(!FileManager.default.fileExists(atPath: store.fileURL("Study/b.tex").path))
    }
}
