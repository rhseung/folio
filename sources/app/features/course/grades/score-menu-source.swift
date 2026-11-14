import FolioDomain
import SwiftUI

@MainActor
struct ScoreMenuSource: ItemMenuSource {
    let model: CourseGradesModel
    let entry: ScoreEntry

    var commands: [ScoreMenuCommand] { ScoreMenuCommand.commands(excused: entry.excused) }

    func row(_ command: ScoreMenuCommand) -> MenuRow {
        switch command {
        case .counts(let on): MenuRow(command, .menuCounts, "checkmark.circle", .check(on) { model.setExcused(entry, !$0) })
        case .edit: .edit(command) { model.editingEntry = entry }
        case .remove: .remove(command) { model.remove(entry) }
        }
    }
}
