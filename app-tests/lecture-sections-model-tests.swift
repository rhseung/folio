import FolioActions
import FolioAI
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import PDFKit
import Testing
@testable import Folio

/// A lecture's units (#321): proposed in the add sheet, edited on the split screen, and drawn where its progress shows.
@MainActor
struct LectureSectionsModelTests {
    let workspace: Workspace
    let slides: FolioDomain.Material
    let matching: UUID

    init() throws {
        workspace = try fixtureWorkspace()
        workspace.run(MaterialTrack(course: graphTheory))
        slides = try #require(workspace.course(graphTheory)?.file.materials.first { $0.path == "Lectures/05_Matchings.pdf" })
        matching = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
    }

    var file: CourseFile { workspace.course(graphTheory)!.file }

    /// A file outside the course, as the add sheet gets it.
    func incoming(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "folio-sections-\(UUID().uuidString)").appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: url)
        return url
    }

    func proposal(_ units: [FolioDomain.Unit]) -> LectureSplit {
        let found = LectureSplit([.init(title: "Matchings", firstPage: 1, lastPage: 1), .init(title: "Berge", firstPage: 9, lastPage: 9)], pageCount: 16)!
        var split = SectionMatch.match(found, units: units)
        split.setUnit(units.first { $0.title == "매칭" }?.id, of: 0, match: .name)
        return split
    }

    func settle(_ model: ImportPlaceModel) async {
        for _ in 0..<50 {
            if case .reading? = model.sections(of: model.rows[0]) { await Task.yield() } else { return }
        }
    }

    // MARK: The add sheet

    @Test func aLectureComesInWithTheSectionsKept() async throws {
        let course = try #require(workspace.course(graphTheory))
        let url = try incoming("06_Matchings II.pdf")
        let model = ImportPlaceModel(workspace: workspace, course: course, files: [url], places: []) { _, units, progress in
            progress(16, 16)
            return .found(proposal(units), .outline)
        }
        await settle(model)
        let row = model.rows[0]
        #expect(model.opened == [0])
        #expect(model.sectionsLine(row) == "단원 2구역 · 목차에서")
        var split = try #require(model.edit(0))
        split.moveBoundary(after: 0, to: 10)
        model.setSplit(split, of: 0)
        model.confirm()

        let f = file
        let m = try #require(f.materials.first { $0.path.hasSuffix("06_Matchings II.pdf") })
        #expect(f.units.first { $0.id == matching }?.lecturePages == [UnitPages(materialId: m.id, firstPage: 1, lastPage: 10)])
        #expect(f.units.first { $0.title == "Berge" }?.lecturePages == [UnitPages(materialId: m.id, firstPage: 11, lastPage: 16)])
    }

    /// Put off, the file comes in unsplit, but what was proposed comes back on asking; a row turned into an assignment
    /// takes no sections at all.
    @Test func putOffOrNoLongerALectureWritesNoSections() async throws {
        let course = try #require(workspace.course(graphTheory))
        let model = ImportPlaceModel(workspace: workspace, course: course, files: [try incoming("07_Flows.pdf")],
                                     places: MaterialIntake.places(assignmentFolders: ["HW01"])) { _, units, _ in .found(proposal(units), .claude) }
        await settle(model)
        model.later(0)
        #expect(model.sectionsLine(model.rows[0]) == "단원 구간 없음 · 나중에 나누기")
        #expect(model.cuts(model.rows[0]) == nil)
        model.takeBack(0)
        #expect(model.sectionsLine(model.rows[0]) == "단원 2구역 · Claude 제안")
        model.setFolder("Assignments/HW01", for: [0])
        #expect(model.sections(of: model.rows[0]) == nil && model.cuts(model.rows[0]) == nil)
    }

    @Test func nothingFoundSplitsByHand() async throws {
        let course = try #require(workspace.course(graphTheory))
        let model = ImportPlaceModel(workspace: workspace, course: course, files: [try incoming("a.pdf"), try incoming("b.pdf")], places: []) { _, _, _ in
            .nothing(pageCount: 12)
        }
        await settle(model)
        // Two files: each keeps to its line.
        #expect(model.opened.isEmpty)
        #expect(model.sectionsLine(model.rows[0]) == "목차와 슬라이드 제목을 찾지 못했습니다")
        model.splitByHand(0)
        #expect(model.edit(0)?.sections.map(\.pages) == [1...12] && model.opened == [0])
        // One zone for no unit writes nothing.
        #expect(model.cuts(model.rows[0]) == nil)
    }

    /// A deck without an outline splits at its divider slides, a long title (nine words) included; titles that name no
    /// unit are proposed as new ones.
    @Test func theReaderSplitsADeckAtItsDividers() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "folio-deck-\(UUID().uuidString).pdf")
        try SampleLecture.write(to: url)
        let units = file.units
        let found = await LectureReader.find(url, units: units, claude: nil)
        guard case .found(let split, .titles) = found else {
            Issue.record("\(found)")
            return
        }
        #expect(split.sections.map(\.pages) == [1...8, 9...16, 17...24])
        #expect(split.sections.map(\.title) == ["Matchings", "Hall's theorem", "Augmenting paths and Berge's theorem in simple bipartite graphs"])
        #expect(split.sections.allSatisfy { $0.isNew })
        let missing = await LectureReader.find(URL(filePath: "/nonexistent.pdf"), units: units, claude: nil)
        #expect(missing == .unreadable)
    }

    // MARK: The split screen and the bars

    @Test func theSplitScreenSavesTheWholeSplit() async throws {
        let course = try #require(workspace.course(graphTheory))
        let model = FileViewModel(workspace: workspace, course: course, subject: .material(slides.id))
        #expect(model.canSplit)
        let document = PDFDocument()
        for i in 0..<10 { document.insert(PDFPage(), at: i) }
        let controller = PDFController(document: document, page: 0)
        await model.startSplit(controller)
        // The fixture's file isn't a PDF to read: one zone to cut by hand, and the screen says so.
        #expect(model.splitting?.sections.map(\.pages) == [1...10])
        #expect(model.splitNote == String(localized: .fileViewSplitNothing))
        model.splitting?.split(at: 5)
        model.splitting?.setUnit(matching, of: 1)
        model.saveSplit()
        #expect(model.splitting == nil)
        #expect(file.units.first { $0.id == matching }?.lecturePages == [UnitPages(materialId: slides.id, firstPage: 5, lastPage: 10)])

        // Opened again, it starts from what the course holds.
        await model.startSplit(controller)
        #expect(model.splitting?.sections.map(\.pages) == [1...4, 5...10] && model.splitting?.sections[1].unit == matching)
    }

    /// Cancelled, the screen closes and the course is as it was; opened again, it starts over.
    @Test func cancellingTheSplitScreenWritesNothing() async throws {
        let course = try #require(workspace.course(graphTheory))
        let model = FileViewModel(workspace: workspace, course: course, subject: .material(slides.id))
        let document = PDFDocument()
        for i in 0..<10 { document.insert(PDFPage(), at: i) }
        let controller = PDFController(document: document, page: 0)
        await model.startSplit(controller)
        model.splitting?.split(at: 4)
        model.splitting?.split(at: 8)
        model.splitting?.setUnit(matching, of: 2)
        model.cancelSplit()
        #expect(model.splitting == nil)
        #expect(!file.isSplit(slides.id))
        #expect(file.units.first { $0.id == matching }?.lecturePages.isEmpty == true)

        await model.startSplit(controller)
        #expect(model.splitting?.sections.map(\.pages) == [1...10])
    }

    // MARK: Claude (#450)

    /// What a stand-in Claude proposes: two new units over ten pages. Each call makes new section ids.
    var claudes: LectureSplit {
        var split = LectureSplit([.init(title: "Overview", firstPage: 1, lastPage: 1), .init(title: "IP", firstPage: 4, lastPage: 4)], pageCount: 10)!
        for i in split.sections.indices { split.makeNew(i) }
        return split
    }

    func standIn(_ answer: ClaudeFinding, off: String? = nil, asked: (@MainActor () -> Void)? = nil) -> LectureClaude {
        LectureClaude(off: { off }, ask: { _, _ in
            asked?()
            return answer
        })
    }

    /// Claude reads every page, not only the titles: each page's text goes under its title, and the divider slides,
    /// which have hardly any words, go as pictures.
    @Test func claudeGetsEachPagesTextAndPicturesOfTheDividers() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "folio-deck-\(UUID().uuidString).pdf")
        try SampleLecture.write(to: url)
        let reply = #"{"sections":[{"title":"Matchings","firstPage":1,"unit":"매칭"},{"title":"Hall","firstPage":9,"unit":null}]}"#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let found = await LectureReader.askClaude(url, units: file.units, claude: ClaudeClient(provider: fake))
        guard case .found(let split) = found else {
            Issue.record("\(found)")
            return
        }
        #expect(split.sections.map(\.pages) == [1...8, 9...24] && split.sections[0].unit == matching)

        let content = try #require(await fake.requests.first?.messages.first?.content)
        guard case .text(let text, _) = content[0] else {
            Issue.record("text first")
            return
        }
        #expect(text.contains("<pages count=\"24\">") && text.contains("## 9: Hall's theorem"))
        // A content slide's own words, past its title.
        let pages = text.components(separatedBy: "## ").dropFirst()
        #expect(pages.filter { $0.contains("\n") }.count > 12)
        let pictures = content.compactMap { block -> Data? in
            if case .image(let data, "image/jpeg", _) = block { data } else { nil }
        }
        #expect(!pictures.isEmpty && pictures.count <= LecturePage.maxImages)
        #expect(pictures.allSatisfy { $0.starts(with: [0xFF, 0xD8]) })
        #expect(content.contains(.text("Page 9:")))
    }

    /// The button asks Claude over a split the course already holds; its answer is on screen, not in the file, until
    /// "저장".
    @Test func claudesSplitReplacesTheOneShownAndWritesNothing() async throws {
        workspace.run(MaterialSplit(course: graphTheory, material: slides.id, sections: [LectureCut(unit: matching, firstPage: 3, lastPage: 8)]))
        let before = file
        let course = try #require(workspace.course(graphTheory))
        let model = FileViewModel(workspace: workspace, course: course, subject: .material(slides.id))
        let claudes = claudes
        model.lectureClaude = standIn(.found(claudes))
        let document = PDFDocument()
        for i in 0..<10 { document.insert(PDFPage(), at: i) }
        await model.startSplit(PDFController(document: document, page: 0))
        #expect(model.canAskClaude && model.claudeSplitOff == nil)
        await model.splitWithClaude()
        #expect(model.splitting == claudes && model.splitNote == nil && !model.askingClaude)
        #expect(file == before)

        model.lectureClaude = standIn(.failed("요청이 실패했습니다"))
        model.splitting?.split(at: 8)
        let edited = model.splitting
        await model.splitWithClaude()
        // A failure keeps what was on screen and says why.
        #expect(model.splitting == edited && model.splitNote == "Claude가 나누지 못했습니다. 요청이 실패했습니다")
        model.saveSplit()
        #expect(file.units.first { $0.title == "IP" } != nil)
    }

    @Test func withoutClaudeTheButtonIsOffAndSaysWhy() async throws {
        let course = try #require(workspace.course(graphTheory))
        let model = FileViewModel(workspace: workspace, course: course, subject: .material(slides.id))
        var asked = false
        model.lectureClaude = standIn(.found(claudes), off: "연결 안 됨") { asked = true }
        let document = PDFDocument()
        for i in 0..<10 { document.insert(PDFPage(), at: i) }
        await model.startSplit(PDFController(document: document, page: 0))
        #expect(!model.canAskClaude && model.claudeSplitOff == "연결 안 됨")
        await model.splitWithClaude()
        #expect(!asked && model.splitting?.sections.map(\.pages) == [1...10])

        let sheet = ImportPlaceModel(workspace: workspace, course: course, files: [try incoming("08_Cuts.pdf")], places: [],
                                     find: { _, _, _ in .nothing(pageCount: 10) }, claude: standIn(.found(claudes), off: "연결 안 됨") { asked = true })
        await settle(sheet)
        #expect(!sheet.canAskClaude(0) && sheet.claudeNote(sheet.rows[0]) == "연결 안 됨")
        sheet.askClaude(0)
        #expect(!asked && sheet.asking.isEmpty)
    }

    /// In the add sheet, Claude's reading takes the place of what the titles proposed, and only the sheet's own button
    /// brings the file in with it.
    @Test func theAddSheetTakesClaudesSplitInPlaceOfTheTitles() async throws {
        let course = try #require(workspace.course(graphTheory))
        let claudes = claudes
        let model = ImportPlaceModel(workspace: workspace, course: course, files: [try incoming("09_Network layer.pdf")], places: [],
                                     find: { _, units, _ in .found(proposal(units), .titles) }, claude: standIn(.found(claudes)))
        await settle(model)
        #expect(model.sectionsLine(model.rows[0]) == "단원 2구역 · 슬라이드 제목에서" && model.canAskClaude(0))
        let before = file
        model.askClaude(0)
        #expect(model.sectionsLine(model.rows[0]) == "Claude가 쪽마다 읽는 중…" && !model.canAskClaude(0))
        for _ in 0..<50 where !model.asking.isEmpty { await Task.yield() }
        #expect(model.edit(0) == claudes && model.sectionsLine(model.rows[0]) == "단원 2구역 · Claude 제안")
        #expect(file == before)
        model.confirm()
        #expect(file.units.contains { $0.title == "IP" })

        let failing = ImportPlaceModel(workspace: workspace, course: course, files: [try incoming("10_Routing.pdf")], places: [],
                                       find: { _, _, _ in .nothing(pageCount: 10) }, claude: standIn(.nothing))
        await settle(failing)
        failing.askClaude(0)
        for _ in 0..<50 where !failing.asking.isEmpty { await Task.yield() }
        #expect(failing.sectionsLine(failing.rows[0]) == "Claude가 나눌 곳을 찾지 못했습니다")
        #expect(failing.claudeNote(failing.rows[0]) == nil)
        // Cut by hand, the row has moved on from what Claude couldn't find.
        failing.splitByHand(0)
        #expect(failing.claudeNote(failing.rows[0]) == nil)
    }

    /// With Claude set up, adding a lecture asks Claude straight away, even where the slide titles would split it: their
    /// guess is not what the user wants first. A failure is not covered over by the titles' guess.
    @Test func withClaudeTheReaderAsksClaudeFirst() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "folio-deck-\(UUID().uuidString).pdf")
        try SampleLecture.write(to: url)
        let reply = #"{"sections":[{"title":"Matchings","firstPage":1,"unit":"매칭"},{"title":"Hall","firstPage":9,"unit":null}]}"#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let found = await LectureReader.find(url, units: file.units, claude: ClaudeClient(provider: fake))
        guard case .found(let split, .claude) = found else {
            Issue.record("\(found)")
            return
        }
        #expect(split.sections.map(\.pages) == [1...8, 9...24] && split.sections[0].unit == matching)

        let failed = await LectureReader.find(url, units: file.units, claude: ClaudeClient(provider: FakeProvider(responses: [])))
        guard case .failed(let why, 24) = failed else {
            Issue.record("\(failed)")
            return
        }
        #expect(why.hasPrefix("Claude가 나누지 못했습니다"))

        let course = try #require(workspace.course(graphTheory))
        let sheet = ImportPlaceModel(workspace: workspace, course: course, files: [try incoming("11_Flows.pdf")], places: [],
                                     find: { _, _, _ in .failed(why, pageCount: 10) }, claude: standIn(.nothing))
        await settle(sheet)
        #expect(sheet.sectionsLine(sheet.rows[0]) == why && sheet.claudeNote(sheet.rows[0]) == nil && sheet.canAskClaude(0))
    }

    @Test func theProgressBarReadsTheUnitsItReaches() throws {
        workspace.run(MaterialSplit(course: graphTheory, material: slides.id, sections: [LectureCut(unit: matching, firstPage: 3, lastPage: 8)]))
        let session = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now))?.made)
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.zones(slides.id).map(\.pages) == [1...2, 3...8])
        #expect(model.zones(slides.id).map(\.title) == ["", "매칭"])
        #expect(!model.changed)

        let units = UnitsModel(workspace: workspace, courseId: graphTheory)
        workspace.run(MaterialLinkUnit(course: graphTheory, material: slides.id, unit: matching, linked: true))
        let unit = try #require(file.units.first { $0.id == matching })
        #expect(units.materials(unit, in: file).first { $0.material.id == slides.id }?.pages == 3...8)
    }
}

#if os(macOS)
import AppKit
import SwiftUI

/// The split screen drawn in a window, on `busyDay`'s real deck: closing it or merging zones redraws rows whose zone
/// is gone, which read past the split's end and stopped the app (#179).
@MainActor @Suite(.serialized)
struct LectureSplitScreenTests {
    let workspace: Workspace
    let model: FileViewModel
    let controller: PDFController
    let host: NSHostingView<AnyView>

    init() async throws {
        workspace = try Workspace.scenario(.busyDay)
        let course = try #require(workspace.course(graphTheory))
        let slides = try #require(course.file.lectureFiles.first { course.file.isSplit($0.id) })
        model = FileViewModel(workspace: workspace, course: course, subject: .material(slides.id))
        let document = try #require(PDFDocument(url: model.url))
        #expect(document.pageCount == 24)
        controller = PDFController(document: document, page: 0)
        await model.startSplit(controller)
        host = NSHostingView(rootView: AnyView(PDFContent(model: model, controller: controller).environment(workspace)))
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 1180, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        try await settle()
    }

    func settle() async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
    }

    @Test func cancellingClosesTheScreen() async throws {
        #expect(model.splitting?.sections.count == 3)
        model.cancelSplit()
        try await settle()
        #expect(model.splitting == nil)
    }

    @Test func mergingTheLastZonesKeepsTheRows() async throws {
        model.splitting?.merge(after: 1)
        try await settle()
        #expect(model.splitting?.sections.map(\.pages) == [1...8, 9...24])
        model.cancelSplit()
        try await settle()
        #expect(model.splitting == nil)
    }
}
#endif
