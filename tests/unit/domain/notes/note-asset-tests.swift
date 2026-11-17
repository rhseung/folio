import FolioDomain
import Foundation
import PropertyBased
import Testing

struct NoteAssetTests {
    static let widget = UUID(uuidString: "5E0C1A2B-3C4D-4E5F-8A9B-0C1D2E3F4A5B") ?? UUID()
    static let other = UUID(uuidString: "11111111-2222-4333-8444-555555555555") ?? UUID()

    @Test func kindComesFromTheExtension() {
        #expect(NoteAsset.kind(ofFile: "hall-matching.svg") == .figure)
        #expect(NoteAsset.kind(ofFile: "PLOT.SVG") == .figure)
        #expect(NoteAsset.kind(ofFile: "board-1028.jpg") == .image)
        #expect(NoteAsset.kind(ofFile: "scan.HEIC") == .image)
        #expect(NoteAsset.kind(ofFile: "tutte-proof.pdf") == .file)
        #expect(NoteAsset.kind(ofFile: "data.csv") == .file)
        #expect(NoteAsset.kind(ofFile: "README") == .file)
        #expect(NoteAsset.widget(Self.widget, title: nil).kind == .widget)
    }

    @Test func filesKeepImagesAndOtherFiles() {
        #expect(NoteAsset.Filter.files.admits(.image) && NoteAsset.Filter.files.admits(.file))
        #expect(!NoteAsset.Filter.files.admits(.figure) && !NoteAsset.Filter.files.admits(.widget))
        #expect(NoteAsset.Kind.allCases.allSatisfy(NoteAsset.Filter.all.admits))
        #expect(NoteAsset.Filter.figures.admits(.figure) && !NoteAsset.Filter.figures.admits(.image))
    }

    @Test func useCountsEmbedsLinksAndWidgetBlocks() {
        let body = """
            # 정리
            ![[hall-matching.svg]] 그리고 ![[konig.svg|300]]
            ![증가 경로](../assets/augmenting%20path.svg)
            [증명](<assets/tutte proof.pdf>)
            [다른 노트](notes/hall-matching-2.svg)
            ```cb-widget
            {"id": "\(Self.widget.uuidString)", "height": 320}
            ```
            """
        let use = NoteAssetUse(body)
        #expect(use.files == ["hall-matching.svg", "konig.svg", "augmenting path.svg", "tutte proof.pdf"])
        #expect(use.widgets == [Self.widget])
    }

    @Test func codeBlocksAreExamplesNotUses() {
        let body = """
            ````markdown
            ![[example.svg]]
            ```cb-widget
            {"id": "\(Self.other.uuidString)"}
            ```
            ````
            ~~~cb-widget
            {"id": "\(Self.widget.uuidString)"}
            ~~~
            """
        let use = NoteAssetUse(body)
        #expect(use.files.isEmpty)
        #expect(use.widgets == [Self.widget])
    }

    @Test func anUnclosedWidgetBlockStillCounts() {
        let use = NoteAssetUse("```cb-widget\n{\"id\": \"\(Self.widget.uuidString)\"}")
        #expect(use.widgets == [Self.widget])
    }

    @Test func shelfPutsUnusedFirstAndNewestFirst() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let assets: [NoteAsset] = [
            .file("old.svg", modified: day),
            .file("new.svg", modified: day.addingTimeInterval(60)),
            .file("board.jpg", modified: day.addingTimeInterval(30)),
            .file("used.svg", modified: day.addingTimeInterval(90)),
            .widget(Self.widget, title: "증가 경로 단계", modified: day.addingTimeInterval(10)),
            .widget(Self.other, title: nil, modified: nil),
        ]
        let use = NoteAssetUse("![[used.svg]]\n```cb-widget\n{\"id\": \"\(Self.widget.uuidString)\"}\n```")
        let shelf = NoteAssetShelf(assets, use: use)
        #expect(shelf.unused.map(\.name) == ["new.svg", "board.jpg", "old.svg", ""])
        #expect(shelf.used.map(\.name) == ["used.svg", "증가 경로 단계"])

        let figures = NoteAssetShelf(assets, use: use, filter: .figures)
        #expect(figures.unused.map(\.name) == ["new.svg", "old.svg"])
        #expect(figures.used.map(\.name) == ["used.svg"])

        let searched = NoteAssetShelf(assets, use: use, search: " 경로 ")
        #expect(searched.unused.isEmpty && searched.used.map(\.name) == ["증가 경로 단계"])
        #expect(NoteAssetShelf(assets, use: use, filter: .widgets, search: "svg").isEmpty)
    }

    static let names = Gen.int(in: 0...6).array(of: 0...12)
    static let marks = Gen.bool.array(of: 0...12)
    static let filter = Gen.element(of: NoteAsset.Filter.allCases).map { $0 ?? .all }

    // 어떤 노트, 어떤 거르기에서도 두 묶음은 거른 애셋을 빠짐없이 한 번씩 담고, 각 묶음은 새것부터 놓인다.
    @Test func shelfSplitsWhatTheFilterKeeps() async {
        await propertyCheck(input: Self.names, Self.marks, Self.filter) { picks, marks, filter in
            let pool = ["a.svg", "b.png", "c.pdf", "d.svg", "e.jpg", "f.txt", "g.svg"]
            var seen: Set<String> = []
            let assets = picks.enumerated().compactMap { i, p -> NoteAsset? in
                guard seen.insert(pool[p]).inserted else { return nil }
                return .file(pool[p], modified: i % 3 == 0 ? nil : Date(timeIntervalSince1970: Double(i * 7 % 5)))
            }
            let body = zip(assets, marks).filter(\.1).map { "![[\($0.0.name)]]" }.joined(separator: "\n")
            let use = NoteAssetUse(body)
            let shelf = NoteAssetShelf(assets, use: use, filter: filter)
            let kept = assets.filter { filter.admits($0.kind) }
            #expect(Set(shelf.unused + shelf.used) == Set(kept))
            #expect(shelf.unused.count + shelf.used.count == kept.count)
            #expect(shelf.unused.allSatisfy { !use.contains($0) } && shelf.used.allSatisfy(use.contains))
            for group in [shelf.unused, shelf.used] {
                let dates = group.map { $0.modified ?? .distantPast }
                #expect(dates == dates.sorted(by: >))
            }
        }
    }
}

struct NoteWidgetTitleTests {
    @Test func readsTheTitleOfThePage() {
        #expect(NoteWidget.title("<!doctype html><html><head><title>증가 경로 단계</title></head>") == "증가 경로 단계")
        #expect(NoteWidget.title("<TITLE lang=ko>\n  인접\n  행렬 &amp; 차수 </TITLE>") == "인접 행렬 & 차수")
        #expect(NoteWidget.title("<title>  </title>") == nil)
        #expect(NoteWidget.title("<div>제목 없음</div>") == nil)
    }
}
