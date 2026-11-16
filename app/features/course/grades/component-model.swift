import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ComponentModel {
    let workspace: Workspace
    let course: LoadedCourse
    let component: GradeComponent
    let isNew: Bool
    var pending: PendingAction?
    var name: String
    var group: String
    var weight: Double
    var aggregation: Aggregation
    var expectedCount: Int?

    init(workspace: Workspace, course: LoadedCourse, component: GradeComponent) {
        self.workspace = workspace
        self.course = course
        self.component = component
        isNew = !course.file.components.contains { $0.id == component.id }
        name = component.name
        group = component.group ?? ""
        weight = component.weight
        aggregation = component.aggregation
        expectedCount = component.expectedCount
    }

    var sheetTitle: String { String(localized: isNew ? .componentSheetAdd : .componentSheetEdit) }
    var confirmTitle: String { String(localized: isNew ? .commonAdd : .commonSave) }

    var invalid: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty || weight < 0 || (expectedCount ?? 1) < 1 }

    var count: Int? {
        switch aggregation {
        case .dropLowest(let n), .bestOf(let n): n
        default: nil
        }
    }

    var aggregationOptions: [(Aggregation, String)] {
        let n = count ?? 1
        return [
            (.sum, String(localized: .aggregationSum)), (.mean, String(localized: .aggregationMean)),
            (.single, String(localized: .aggregationSingle)),
            (.dropLowest(n), String(localized: .componentSheetDropLowest)), (.bestOf(n), String(localized: .componentSheetBestOf)),
        ]
    }

    var dropsLowest: Bool { aggregation == .dropLowest(count ?? 1) }

    var countLabel: String { String(localized: dropsLowest ? .componentSheetDropCount : .componentSheetKeepCount) }

    var countValue: Int {
        get { count ?? 1 }
        set { aggregation = dropsLowest ? .dropLowest(newValue) : .bestOf(newValue) }
    }

    var countOptions: [(Int, String)] { (1...10).map { ($0, String(localized: .componentSheetTimes($0))) } }

    func confirm() -> Bool {
        let saved =
            isNew
            ? workspace.run(
                ComponentAdd(
                    id: component.id, course: course.id, name: name, weight: weight, aggregation: aggregation,
                    expectedCount: expectedCount, group: group))
            : workspace.run(
                ComponentSet(
                    course: course.id, component: component.id, name: .set(name), weight: .set(weight),
                    aggregation: .set(aggregation), expectedCount: .set(expectedCount), group: .set(group)))
        return saved != nil
    }

    func remove(then done: @escaping @MainActor () -> Void) {
        pending = workspace.ask(ComponentRemove(course: course.id, component: component.id)) { _ in done() }
    }
}
