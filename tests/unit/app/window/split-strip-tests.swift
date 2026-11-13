import FolioDomain
import Foundation
import Testing

@testable import Folio

struct SplitStripTests {
    let base: LectureSplit

    init() throws {
        var split = try #require(
            LectureSplit(
                [
                    .init(title: "Intro", firstPage: 1, lastPage: 1), .init(title: "Hall", firstPage: 5, lastPage: 5),
                    .init(title: "", firstPage: 9, lastPage: 9),
                ], pageCount: 12))
        split.setUnit(UUID(), of: 0)
        split.makeNew(1)
        base = split
    }

    func names(_ split: LectureSplit) -> (Int) -> String {
        { split.sections[$0].title.isEmpty ? "이름 없는 구역" : split.sections[$0].title }
    }

    // 열을 위에서 아래로 `PageStripModelTests`와 같은 기호로 적는다. `H`는 점이 붙은 펼친 머리(`●` 기존 단원, `○` 새 단원, `·` 단원 없음), `h`는 접힌 머리, `e`는
    // 편집 행이다. `|`는 구획 색이 칠해진 쪽, `*`는 고른 쪽이다.
    func column(_ strip: SplitStrip, _ split: LectureSplit) -> [String] {
        strip.items(split, name: names(split)).map { item in
            func dot(_ s: StripSection) -> String {
                switch s.kind {
                case .held: "●"
                case .new: "○"
                case .none: "·"
                }
            }
            let lead: String =
                switch item.lead {
                case .header(let s, let open)?: (open ? "H" : "h") + dot(s) + s.title
                case .edit(let s)?: "e" + s.label
                case .draft?: "d"
                case nil: ""
                }
            let mark =
                switch item.mark {
                case .plain: ""
                case .tinted: "|"
                case .picked: "*"
                }
            return lead + (item.page.map { " \($0)\(mark)" } ?? "")
        }
    }

    @Test func sectionsAreHeadedAndTintedByWhereTheyGo() {
        let split = base
        let items = SplitStrip().items(split, name: names(split))
        #expect(items[2].mark == .tinted(last: false) && items[3].mark == .tinted(last: true) && items[11].mark == .plain)

        let column = column(SplitStrip(), split)
        #expect(column.count == 12)
        #expect(column[0] == "H●Intro 1|" && column[3] == " 4|")
        #expect(column[4] == "H○Hall 5|" && column[7] == " 8|")
        #expect(column[8] == "H·이름 없는 구역 9" && column[11] == " 12")
    }

    @Test func aFoldedSectionIsItsHeaderAlone() {
        let split = base
        var strip = SplitStrip()
        strip.toggle(split.sections[1].id)
        let column = column(strip, split)
        #expect(column[4] == "h○Hall" && column[5] == "H·이름 없는 구역 9")
        #expect(strip.items(split, name: names(split))[4].mark == .tinted(last: true))
        #expect(strip.itemID(showing: 6, in: split) == .folded(split.sections[1].id) && strip.itemID(showing: 2, in: split) == .page(2))
    }

    @Test func aHeaderChangesItsSectionsPagesAndCancelPutsThemBack() {
        var split = base
        var strip = SplitStrip()
        let before = split
        strip.edit(split.sections[1].id, in: split)
        #expect(column(strip, split)[4] == "e5–8쪽 5*" && !strip.changed(split) && strip.index(in: split) == 1)
        strip.extend(to: 10, in: &split)
        #expect(split.sections.map(\.pages) == [1...4, 5...10, 11...12] && strip.changed(split))
        strip.extend(to: 2, in: &split)
        #expect(split.sections.map(\.pages) == [1...1, 2...10, 11...12])
        strip.extend(to: 30, in: &split)
        #expect(split.sections.map(\.pages) == [1...1, 2...11, 12...12])
        strip.cancel(&split)
        #expect(split == before && strip.editing == nil)
    }

    @Test func applyingKeepsTheChange() {
        var split = base
        var strip = SplitStrip()
        strip.edit(split.sections[0].id, in: split)
        strip.extend(to: 6, in: &split)
        strip.done()
        #expect(split.sections.map(\.pages) == [1...6, 7...8, 9...12] && strip.editing == nil)

        strip.edit(split.sections[2].id, in: split)
        strip.extend(to: 7, in: &split)
        strip.press(3)
        #expect(split.sections.map(\.pages) == [1...6, 7...7, 8...12])
        #expect(strip.editing == nil && strip.anchor == 3)
    }

    @Test func aPickedRangeBecomesASectionToChange() {
        var split = base
        var strip = SplitStrip()
        let before = split
        strip.press(10)
        strip.extend(to: 11, in: &split)
        #expect(split.sections.map(\.pages) == [1...4, 5...8, 9...9, 10...11, 12...12])
        #expect(strip.index(in: split) == 3 && column(strip, split)[9] == "e10–11쪽 10*")
        strip.cancel(&split)
        #expect(split == before)
    }

    @Test func aLongPressTakesUpItsSection() {
        let split = base
        var strip = SplitStrip()
        strip.start(at: 6, in: split)
        #expect(strip.editing == split.sections[1].id && strip.anchor == 5)
    }
}
