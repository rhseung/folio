import FolioDomain
import FolioStorage
import Foundation

@Action(
    "catalog set", "catalog.json을 파일 내용으로 바꾸기. 바뀐 행만 수정 시각이 바뀐다",
    discussion: "`folio catalog show --json`으로 받은 파일을 고쳐서 넣는다. 모르는 필드는 남는다.",
    done: "카탈로그를 바꿨습니다", examples: ["folio catalog set --file catalog.json --dry-run"], phrases: ["카탈로그 수정"])
public struct CatalogSet {
    /// catalog.json 형식의 파일
    @CLIName("file") @FromFile("path") var catalog: Catalog

    public func run(_ ctx: ActionContext) throws {
        try ctx.editCatalog { old in
            func touched<E: Entity>(_ new: [E], _ old: [E]) -> [E] {
                let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                return new.map { item in
                    guard let previous = before[item.id], previous != item else { return item }
                    var item = item
                    item.touch(by: ctx.device, at: ctx.now)
                    return item
                }
            }

            var new = catalog
            new.codes = touched(catalog.codes, old.codes)
            new.categories = touched(catalog.categories, old.categories)
            new.letterGrades = touched(catalog.letterGrades, old.letterGrades)
            new.people = touched(catalog.people, old.people)
            old = new
        }
    }
}
