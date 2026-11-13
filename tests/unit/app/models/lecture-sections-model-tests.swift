import FolioAI
import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import PDFKit
import Testing

@testable import Folio

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

    func incoming(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "folio-sections-\(UUID().uuidString)").appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: url)
        return url
    }

    func proposal(_ units: [FolioDomain.Unit]) -> LectureSplit {
        let found = LectureSplit(
            [.init(title: "Matchings", firstPage: 1, lastPage: 1), .init(title: "Berge", firstPage: 9, lastPage: 9)], pageCount: 16)!
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

    @Test func putOffOrNoLongerALectureWritesNoSections() async throws {
        let course = try #require(workspace.course(graphTheory))
        let model = ImportPlaceModel(
            workspace: workspace, course: course, files: [try incoming("07_Flows.pdf")],
            places: MaterialIntake.places(assignmentFolders: ["HW01"])
        ) { _, units, _ in .found(proposal(units), .claude) }
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
        let model = ImportPlaceModel(
            workspace: workspace, course: course, files: [try incoming("a.pdf"), try incoming("b.pdf")], places: []
        ) { _, _, _ in
            .nothing(pageCount: 12)
        }
        await settle(model)
        #expect(model.opened.isEmpty)
        #expect(model.sectionsLine(model.rows[0]) == "목차와 슬라이드 제목을 찾지 못했습니다")
        model.splitByHand(0)
        #expect(model.edit(0)?.sections.map(\.pages) == [1...12] && model.opened == [0])
        #expect(model.cuts(model.rows[0]) == nil)
    }

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
        #expect(
            split.sections.map(\.title) == [
                "Matchings", "Hall's theorem", "Augmenting paths and Berge's theorem in simple bipartite graphs",
            ])
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
        #expect(model.splitting?.sections.map(\.pages) == [1...10])
        #expect(model.splitNote == String(localized: .fileViewSplitNothing))
        model.splitting?.split(at: 5)
        model.splitting?.setUnit(matching, of: 1)
        model.saveSplit()
        #expect(model.splitting == nil)
        #expect(file.units.first { $0.id == matching }?.lecturePages == [UnitPages(materialId: slides.id, firstPage: 5, lastPage: 10)])

        await model.startSplit(controller)
        #expect(model.splitting?.sections.map(\.pages) == [1...4, 5...10] && model.splitting?.sections[1].unit == matching)
    }

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

    var claudes: LectureSplit {
        var split = LectureSplit(
            [.init(title: "Overview", firstPage: 1, lastPage: 1), .init(title: "IP", firstPage: 4, lastPage: 4)], pageCount: 10)!
        for i in split.sections.indices { split.makeNew(i) }
        return split
    }

    func standIn(_ answer: ClaudeFinding, asked: (@MainActor () -> Void)? = nil) -> LectureClaude {
        LectureClaude(
            off: { nil },
            ask: { _, _ in
                asked?()
                return answer
            })
    }

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
        let pages = text.components(separatedBy: "## ").dropFirst()
        #expect(pages.filter { $0.contains("\n") }.count > 12)
        let pictures = content.compactMap { block -> Data? in
            if case .image(let data, "image/jpeg", _) = block { data } else { nil }
        }
        #expect(!pictures.isEmpty && pictures.count <= LecturePage.maxImages)
        #expect(pictures.allSatisfy { $0.starts(with: [0xFF, 0xD8]) })
        #expect(content.contains(.text("Page 9:")))
    }

    @Test func theSplitScreenOffersClaudeAgainOnlyAfterItFailed() async throws {
        let before = file
        let course = try #require(workspace.course(graphTheory))
        let model = FileViewModel(workspace: workspace, course: course, subject: .material(slides.id))
        let failure = "Claude가 나누지 못했습니다. 요청이 실패했습니다"
        model.lectureClaude = standIn(.failed("요청이 실패했습니다"))
        model.findSplit = { _, _ in .failed(failure, pageCount: 10) }
        let document = PDFDocument()
        for i in 0..<10 { document.insert(PDFPage(), at: i) }
        await model.startSplit(PDFController(document: document, page: 0))
        #expect(model.canRetryClaude && model.splitNote == failure && model.splitting?.sections.map(\.pages) == [1...10])
        await model.retryClaude()
        #expect(model.canRetryClaude && model.splitNote == failure && model.splitting?.sections.map(\.pages) == [1...10])

        let claudes = claudes
        model.lectureClaude = standIn(.found(claudes))
        await model.retryClaude()
        #expect(model.splitting == claudes && model.splitNote == nil && !model.canRetryClaude && !model.askingClaude)
        #expect(file == before)
        model.saveSplit()
        #expect(file.units.first { $0.title == "IP" } != nil)
    }

    @Test func withoutAFailureThereIsNoClaudeToAskAgain() async throws {
        let course = try #require(workspace.course(graphTheory))
        let model = FileViewModel(workspace: workspace, course: course, subject: .material(slides.id))
        let claudes = claudes
        var asked = false
        model.lectureClaude = standIn(.found(claudes)) { asked = true }
        model.findSplit = { _, _ in .found(claudes, .claude) }
        let document = PDFDocument()
        for i in 0..<10 { document.insert(PDFPage(), at: i) }
        await model.startSplit(PDFController(document: document, page: 0))
        #expect(model.splitting == claudes && !model.canRetryClaude)
        await model.retryClaude()
        #expect(!asked)

        let sheet = ImportPlaceModel(
            workspace: workspace, course: course, files: [try incoming("08_Cuts.pdf")], places: [],
            find: { _, _, _ in .nothing(pageCount: 10) }, claude: standIn(.found(claudes)) { asked = true })
        await settle(sheet)
        #expect(!sheet.showsRetry(0))
        sheet.retryClaude(0)
        #expect(!asked && sheet.asking.isEmpty)
    }

    @Test func theAddSheetAsksClaudeAgainAfterItFailed() async throws {
        let course = try #require(workspace.course(graphTheory))
        let claudes = claudes
        let failure = "Claude가 나누지 못했습니다. 요청이 실패했습니다"
        let model = ImportPlaceModel(
            workspace: workspace, course: course, files: [try incoming("09_Network layer.pdf")], places: [],
            find: { _, _, _ in .failed(failure, pageCount: 10) }, claude: standIn(.found(claudes)))
        await settle(model)
        #expect(model.sectionsLine(model.rows[0]) == failure && model.showsRetry(0))
        let before = file
        model.retryClaude(0)
        #expect(model.sectionsLine(model.rows[0]) == "Claude가 쪽마다 읽는 중…" && model.showsRetry(0) && !model.canRetryClaude(0))
        for _ in 0..<50 where !model.asking.isEmpty { await Task.yield() }
        #expect(model.edit(0) == claudes && model.sectionsLine(model.rows[0]) == "단원 2구역 · Claude 제안" && !model.showsRetry(0))
        #expect(file == before)
        model.confirm()
        #expect(file.units.contains { $0.title == "IP" })

        let failing = ImportPlaceModel(
            workspace: workspace, course: course, files: [try incoming("10_Routing.pdf")], places: [],
            find: { _, _, _ in .failed(failure, pageCount: 10) }, claude: standIn(.nothing))
        await settle(failing)
        failing.retryClaude(0)
        for _ in 0..<50 where !failing.asking.isEmpty { await Task.yield() }
        #expect(failing.sectionsLine(failing.rows[0]) == "Claude가 나눌 곳을 찾지 못했습니다" && failing.showsRetry(0))
        failing.splitByHand(0)
        #expect(!failing.showsRetry(0))
    }

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
        let sheet = ImportPlaceModel(
            workspace: workspace, course: course, files: [try incoming("11_Flows.pdf")], places: [],
            find: { _, _, _ in .failed(why, pageCount: 10) }, claude: standIn(.nothing))
        await settle(sheet)
        #expect(sheet.sectionsLine(sheet.rows[0]) == why && sheet.showsRetry(0))
    }

    @Test func theProgressBarReadsTheUnitsItReaches() throws {
        workspace.run(
            MaterialSplit(course: graphTheory, material: slides.id, sections: [LectureCut(unit: matching, firstPage: 3, lastPage: 8)]))
        let session = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now))?.made)
        let model = SessionSheetModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.zones(slides.id).map(\.pages) == [1...2, 3...8])
        #expect(model.zones(slides.id).map(\.title) == ["", "매칭"])
        #expect(!model.changed)

        let units = UnitsModel(workspace: workspace, courseId: graphTheory)
        let unit = try #require(file.units.first { $0.id == matching })
        let row = try #require(units.materials(unit, in: file).first { $0.material.id == slides.id })
        #expect(row.pages == 3...8)
        #expect(row.own)
        #expect(ReviewModel.lectures(of: unit, in: file).first { $0.material.id == slides.id }?.page == 3)
    }

    @Test func theMaterialsPageShowsASplitUnitAsTheFilesOwnNotAsThroughAClass() throws {
        workspace.run(
            MaterialSplit(course: graphTheory, material: slides.id, sections: [LectureCut(unit: matching, firstPage: 3, lastPage: 8)]))
        let model = MaterialsModel(workspace: workspace, course: try #require(workspace.course(graphTheory)))
        #expect(model.unitIds(of: slides.id).isEmpty)
        #expect(!model.unitsViaSessions(of: slides.id).contains(matching))
        #expect(model.splitPages(of: slides.id, unit: matching) == "3–8쪽")
        #expect(model.linkLine(slides).contains(String(localized: .materialsLinkUnits("매칭"))))
        #expect(!model.linkLine(slides).contains(String(localized: .materialsLinkUnitsViaSessions("매칭"))))
    }
}

#if os(macOS)
import AppKit
import SwiftUI

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
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 1180, height: 720), styleMask: [.borderless], backing: .buffered,
            defer: false)
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
