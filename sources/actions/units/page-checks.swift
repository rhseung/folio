import FolioDomain
import FolioStorage
import Foundation

func checkPages(_ first: Int, _ last: Int) throws {
    guard first >= 1, first <= last else { throw ActionError.rule(String(localized: .errorUnitPagesRange(first, last))) }
}

func checkCuts(_ cuts: [LectureCut], in f: CourseFile) throws {
    for cut in cuts {
        try checkPages(cut.firstPage, cut.lastPage)
        guard !f.units.contains(where: { $0.id == cut.unit }) else { continue }
        guard !(cut.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ActionError.notFound(String(localized: .errorNotFoundItem(String(localized: .valueUnit))))
        }
        if let parent = cut.parent { _ = try index(parent, in: f.units, .valueUnit) }
    }
}
