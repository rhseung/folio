import FolioActions
import FolioDomain
import Foundation

extension CatalogShow: QueryOutput {
    func say(_ catalog: Catalog, _ r: Resolver) throws {
        FolioCLI.say(String(localized: .catalogShowCodes).styled(.bold) + "  " + catalog.codes.map(\.prefix).joined(separator: " "))
        FolioCLI.say(
            String(localized: .catalogShowLetterGrades).styled(.bold) + "  " + catalog.letterGrades.map(\.symbol).joined(separator: " "))
        FolioCLI.say(
            String(localized: .catalogShowCategories).styled(.bold) + "  "
                + String(localized: .catalogShowCategoryCount(catalog.categories.count)))
        FolioCLI.say(String(localized: .catalogShowPeople).styled(.bold) + "  " + catalog.people.map(\.name).joined(separator: ", "))
        FolioCLI.say(
            String(localized: .catalogShowHandbooks).styled(.bold) + "  "
                + catalog.handbooks.map { String($0.year) }.joined(separator: ", "))
    }
}
