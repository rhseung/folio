import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers

struct PDFPagesTests {
    func deck() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "deck-\(UUID().uuidString).pdf")
        try SampleLecture.write(to: url)
        return url
    }

    @Test func eachPageReadsItsTitleAndText() throws {
        let pdf = try #require(PDFPages.open(try deck()))
        #expect(pdf.pageCount == SampleLecture.titles.count)
        let divider = PDFPages.text(of: try #require(pdf.page(at: 0)), number: 1)
        #expect(divider.title == "Matchings" && divider.words == 0 && divider.page == 1)
        let slide = PDFPages.text(of: try #require(pdf.page(at: 1)), number: 2)
        #expect(slide.title == "Definitions")
        #expect(slide.text.contains("Slide 2, point 1"))

        // Three body lines of about eleven words, the title not counted.
        #expect(slide.words > 20)
        #expect(!slide.text.contains(PageText.figure) && !slide.text.contains("\n\n"))
    }

    @Test func aPagePictureIsAJPEGAtTheReadingEdge() throws {
        let pdf = try #require(PDFPages.open(try deck()))
        let page = try #require(pdf.page(at: 3))
        let jpeg = try #require(PDFPages.jpeg(page))
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let w = try #require(props[kCGImagePropertyPixelWidth] as? Int), h = try #require(props[kCGImagePropertyPixelHeight] as? Int)
        #expect(max(w, h) == ReadingLimit.imageEdge && w > h)
    }

    @Test func notAPDFOpensNothing() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "not-\(UUID().uuidString).pdf")
        try Data("placeholder".utf8).write(to: url)
        #expect(PDFPages.open(url) == nil)
    }

    @Test func noteImagesAreFoundInsideTheCourseOnly() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first { $0.url.lastPathComponent == "EC4207 그래프 이론" })
        let written = try store.addNoteAsset(named: "board.png", data: Data("png".utf8))
        let url = store.newNoteURL(title: "그림", format: .markdown)
        try store.createNote(at: url, text: "")
        let note = NoteFile(url: url, meta: NoteMeta())
        let found = store.noteImageFiles(of: note, body: "![a](\(written)) ![[board.png]] ![x](../../secret.png) ![y](assets/none.png)")
        #expect(found.map(\.written) == [written, "board.png", "../../secret.png", "assets/none.png"])
        #expect(found.map(\.path) == ["Notes/assets/board.png", "Notes/assets/board.png", nil, nil])

        // Not an image: nothing to shrink, and a path out of the course reads nothing.
        #expect(store.pictureJPEG("Notes/assets/board.png") == nil)
        #expect(store.pictureJPEG("../secret.png") == nil)
    }
}
