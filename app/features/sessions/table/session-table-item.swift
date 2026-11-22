import FolioDomain
import SwiftUI

struct SessionTableItem: View {
    @Bindable var model: SessionsModel
    let course: LoadedCourse
    let entry: SessionTableEntry
    let table: SessionTable
    var other = false
    var minHeight = Theme.Size.touchTarget

    var body: some View {
        if case .deadline = entry.item {
            SessionDeadlineRow(model: model, entry: entry, other: other)
        } else {
            SessionBlock(model: model, course: course, entry: entry, table: table, other: other, minHeight: minHeight)
        }
    }
}
