import FolioDomain
import FolioStorage
import Foundation

extension GradeComponent {
    var normalized: GradeComponent {
        var c = self
        c.name = c.name.trimmingCharacters(in: .whitespaces)
        c.group = c.group?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        if c.aggregation == .single { c.expectedCount = nil }
        return c
    }
}
