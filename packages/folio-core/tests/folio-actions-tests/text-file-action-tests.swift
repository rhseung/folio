import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
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

    static let tex = "Exams/Midterm/Problems.tex"

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

    @Test func aPDFIsNotText() throws {
        let m = try material("Exams/Midterm/Problems.pdf")
        #expect(throws: ActionError.rule("텍스트 파일이 아니라서 쓸 수 없습니다: Exams/Midterm/Problems.pdf")) {
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

    @Test func buildPlacesThePDFNextToItsSource() throws {
        let tex = try material(Self.tex)
        let built = FileManager.default.temporaryDirectory.appending(path: "folio-build-\(UUID().uuidString).pdf")
        try Data("%PDF-1.7 built".utf8).write(to: built)
        let ctx = try run(MaterialBuild(course: Self.course, material: tex.id, pdf: built.path))
        #expect(ctx.changes.first == Change(.changed, "2026-3/EC4207 그래프 이론/Exams/Midterm/Problems.pdf"))
        #expect(try store.readText("Exams/Midterm/Problems.pdf") == "%PDF-1.7 built")
        let pdf = try material("Exams/Midterm/Problems.pdf")
        #expect(try material(Self.tex).sourceOf == pdf.id)
    }

    @Test func buildAddsAPDFThatWasNotThere() throws {
        try store.writeText("Assignments/HW03/hw.tex", text: "\\documentclass{article}\n")
        try run(MaterialTrack(course: Self.course))
        let tex = try material("Assignments/HW03/hw.tex")
        let built = FileManager.default.temporaryDirectory.appending(path: "folio-build-\(UUID().uuidString).pdf")
        try Data("%PDF".utf8).write(to: built)
        let ctx = try run(MaterialBuild(course: Self.course, material: tex.id, pdf: built.path))
        #expect(ctx.changes.first == Change(.added, "2026-3/EC4207 그래프 이론/Assignments/HW03/hw.pdf"))
        #expect(try material("Assignments/HW03/hw.tex").sourceOf == material("Assignments/HW03/hw.pdf").id)
    }

    @Test func buildTakesOnlyTex() throws {
        let m = try material("Exams/Midterm/Problems.pdf")
        #expect(throws: ActionError.rule("LaTeX 파일(.tex)만 PDF로 만듭니다: Exams/Midterm/Problems.pdf")) {
            try run(MaterialBuild(course: Self.course, material: m.id))
        }
    }

    @Test(.enabled(if: TexEngine.locate() != nil, "Tectonic is not installed"))
    func buildRunsTectonic() throws {
        try store.writeText("Assignments/HW03/hw.tex", text: "\\documentclass{article}\n\\begin{document}\nHello\n\\end{document}\n")
        try run(MaterialTrack(course: Self.course))
        try run(MaterialBuild(course: Self.course, material: try material("Assignments/HW03/hw.tex").id))
        let pdf = try Data(contentsOf: store.fileURL("Assignments/HW03/hw.pdf"))
        #expect(pdf.starts(with: Data("%PDF".utf8)))
    }

    @Test(.enabled(if: TexEngine.locate() != nil, "Tectonic is not installed"))
    func aBrokenDocumentNamesItsLine() throws {
        try store.writeText("Assignments/HW03/hw.tex", text: "\\documentclass{article}\n\\begin{document}\n\\foo\n\\end{document}\n")
        try run(MaterialTrack(course: Self.course))
        let tex = try material("Assignments/HW03/hw.tex")
        #expect(throws: ActionError.rule("PDF를 만들지 못했습니다.\nhw.tex:3: Undefined control sequence")) {
            try run(MaterialBuild(course: Self.course, material: tex.id))
        }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL("Assignments/HW03/hw.pdf").path))
    }
}
