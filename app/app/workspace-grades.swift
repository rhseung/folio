import FolioDomain
import Foundation

extension Workspace {

    /// Categories of undeclared programs stay in catalog.json but out of every requirement view.
    var requirementCatalog: Catalog { catalog.scoped(to: transcript.graduation.programs) }

    /// A draft in the default mail app. mailto can't choose the sending account; the mail app's default account does.
    func mailURL(to address: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = address
        return address.isEmpty ? nil : c.url
    }
}
