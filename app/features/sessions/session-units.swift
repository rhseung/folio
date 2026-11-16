import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

struct SessionUnits {
    let file: CourseFile
    let session: Session
    let linked: [FolioDomain.Unit]
    let shown: [FolioDomain.Unit]
    let missing: Bool

    init(_ session: Session, in file: CourseFile, now: Date) {
        self.file = file
        self.session = session
        linked = file.units(of: session)
        shown = UnitTree.deepest(linked, in: file.units)
        missing = file.needsUnits(session, at: now)
    }

    var offered: Bool { !file.units.isEmpty && (!linked.isEmpty || !session.skipsReview) }

    var titles: String { shown.map(\.title).joined(separator: " · ") }

    var symbol: String { missing ? "exclamationmark.triangle.fill" : linked.isEmpty ? "plus" : "link" }

    var label: String { shown.isEmpty ? String(localized: missing ? .sessionsUnitsNeeded : .sessionsUnitsLink) : titles }

    var help: String {
        missing
            ? String(localized: .sessionsUnitsMissingHelp)
            : shown.isEmpty
                ? String(localized: .sessionsUnitsHelp)
                : shown.map(\.title).joined(separator: "\n")
    }

    var progress: (material: UUID, pages: ClosedRange<Int>)? { file.splitProgress(of: session) }
}
