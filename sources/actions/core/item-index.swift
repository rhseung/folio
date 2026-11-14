import FolioDomain
import FolioStorage
import Foundation

func index<E: Identifiable>(_ id: E.ID, in items: [E], _ what: LocalizedStringResource) throws -> Int {
    guard let i = items.firstIndex(where: { $0.id == id }) else {
        throw ActionError.notFound(String(localized: .errorNotFoundItem(String(localized: what))))
    }
    return i
}
