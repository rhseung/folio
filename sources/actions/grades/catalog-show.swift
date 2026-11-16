import FolioDomain
import Foundation

@Query(
    "catalog show", "카탈로그 요약. --json이면 catalog.json 전체",
    examples: ["folio catalog show", "folio catalog show --json > catalog.json"], phrases: ["카탈로그", "과목 코드 목록", "교수 목록"])
public struct CatalogShow {
    public func read(_ ctx: ReadContext) throws -> Catalog { try ctx.catalog() }
}
