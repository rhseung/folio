import CoreGraphics
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import PDFKit
import Testing
@testable import Folio

@MainActor
struct FileViewModelTests {
    /// 그래프 이론 with its files tracked, `Study/Problems.pdf` made a real three-page PDF (the fixture's PDFs are only
    /// bytes), and a markdown file and one no viewer knows beside it.
    func course() throws -> (Workspace, LoadedCourse) {
        let workspace = try fixtureWorkspace()
        let folder = try #require(workspace.course(graphTheory)).store.url
        var box = CGRect(x: 0, y: 0, width: 60, height: 80)
        let pdf = try #require(CGContext(folder.appending(path: "Study/Problems.pdf") as CFURL, mediaBox: &box, nil))
        for _ in 0..<3 {
            pdf.beginPDFPage(nil)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        try Data("# 요약".utf8).write(to: folder.appending(path: "Study/summary.md"))
        try Data([1, 2, 3]).write(to: folder.appending(path: "Study/data.zzq"))
        workspace.run(MaterialTrack(course: graphTheory))
        return (workspace, try #require(workspace.course(graphTheory)))
    }

    func material(_ path: String, in course: LoadedCourse) throws -> UUID {
        try #require(course.file.materials.first { $0.path == path }).id
    }

    func views(_ workspace: Workspace, _ course: LoadedCourse, _ id: UUID) -> Int {
        ((try? course.store.log.readAll()) ?? []).events(MaterialViewEvent.self).filter { $0.event.materialId == id }.count
    }

    @Test func picksTheRendererByFormat() async throws {
        let (workspace, course) = try course()
        func loaded(_ path: String) async throws -> FileViewModel.Loaded {
            let model = FileViewModel(workspace: workspace, course: course, subject: .material(try material(path, in: course)))
            await model.load(page: nil)
            return model.loaded
        }
        guard case .pdf = try await loaded("Study/Problems.pdf") else { Issue.record("PDF"); return }
        guard case .markdown(let text) = try await loaded("Study/summary.md") else { Issue.record("markdown"); return }
        #expect(text == "# 요약")
        guard case .unsupported = try await loaded("Study/data.zzq") else { Issue.record("unsupported"); return }
    }

    @Test func editsTrackedTextAndTexNotesOnly() throws {
        let (workspace, course) = try course()
        let tex = FileViewModel(workspace: workspace, course: course, subject: .material(try material("Study/Problems.tex", in: course)))
        let pdf = FileViewModel(workspace: workspace, course: course, subject: .material(try material("Study/Problems.pdf", in: course)))
        #expect(tex.editsInPlace && !pdf.editsInPlace)
        // A file outside any course is only shown.
        let admin = FileViewModel(workspace: workspace, course: nil, subject: .file(course.store.url.appending(path: "Study/Problems.tex")))
        #expect(!admin.editsInPlace && admin.opensElsewhere)

        let note = try #require(try course.store.notes().first { $0.url.pathExtension == "md" })
        let shown = FileViewModel(workspace: workspace, course: course, subject: .note(note))
        // A markdown note is read here; the note is the app's own, with no other app to open it in.
        #expect(!shown.editsInPlace && !shown.opensElsewhere)
    }

    @Test func opensAtTheRequestedPageOrWhereItWasLeft() async throws {
        let (workspace, course) = try course()
        let id = try material("Study/Problems.pdf", in: course)
        func open(_ page: Int?, remembers: Bool = true) async -> (FileViewModel, PDFController?) {
            let model = FileViewModel(workspace: workspace, course: course, subject: .material(id), remembersPage: remembers)
            await model.load(page: page)
            guard case .pdf(let c) = model.loaded else { return (model, nil) }
            return (model, c)
        }

        // A page past the end is the last one.
        let (_, past) = await open(10)
        #expect(past?.page == 2)

        // Left where it opened: nothing to remember.
        let (first, firstPDF) = await open(nil)
        #expect(firstPDF?.page == 0)
        first.closed(at: 0)
        #expect(views(workspace, course, id) == 0)
        first.closed(at: 1)
        #expect(views(workspace, course, id) == 1)

        let (_, again) = await open(nil)
        #expect(again?.page == 1)

        // A review's source leaves the resume page alone.
        let (review, _) = await open(2, remembers: false)
        review.closed(at: 2)
        #expect(views(workspace, course, id) == 1)
    }
}
