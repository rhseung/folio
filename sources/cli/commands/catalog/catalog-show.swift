import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension CatalogCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .catalogShowAbstract), discussion: String(localized: .catalogShowDiscussion))
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let catalog = try CLI.context(g).catalog()
            if g.json { return try printJSON(catalog) }
            say(String(localized: .catalogShowCodes).styled(.bold) + "  " + catalog.codes.map(\.prefix).joined(separator: " "))
            say(
                String(localized: .catalogShowLetterGrades).styled(.bold) + "  " + catalog.letterGrades.map(\.symbol).joined(separator: " ")
            )
            say(
                String(localized: .catalogShowCategories).styled(.bold) + "  "
                    + String(localized: .catalogShowCategoryCount(catalog.categories.count)))
            say(String(localized: .catalogShowPeople).styled(.bold) + "  " + catalog.people.map(\.name).joined(separator: ", "))
            say(
                String(localized: .catalogShowHandbooks).styled(.bold) + "  "
                    + catalog.handbooks.map { String($0.year) }.joined(separator: ", "))
        }
    }
}
