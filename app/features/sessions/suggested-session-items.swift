import FolioActions
import FolioDomain
import SwiftUI

struct SuggestedSessionItems: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openURL) private var openURL
    @Environment(\.itemSheets) private var sheets
    let item: Workspace.SuggestedSession
    let primary: Bool
    let openNote: (UUID) -> Void
    var editTimes: (() -> Void)?

    var body: some View {
        let model = SessionMenuModel(workspace: workspace, courseId: item.courseId)
        let today = model.isToday(item)
        if let link = model.link(of: item) {
            Button(.sessionsJoinOnline, systemImage: "video") { JoinOnlineButton.join(link, openURL) }
            Divider()
        }
        if primary {
            if today {
                Button(.sessionsOpenRoughNote, systemImage: "pencil.line") { if let id = model.roughNote(item) { openNote(id) } }
            } else {
                Button(.sessionsMakeSession, systemImage: "plus") { model.make(item) }
            }
        }
        if today { Button(.sessionsMakeSessionOnly, systemImage: "plus") { model.make(item) } }
        Button(.sessionsRecord, systemImage: "record.circle") { model.record(item) }.disabled(model.isRecording)
        Divider()
        Button(.sessionsMarkAbsent, systemImage: "person.crop.circle.badge.xmark") { model.make(item, attendance: .absent) }
            .disabled(!model.canMark(item, .absent))
        Button(.sessionsMarkExcused, systemImage: "person.crop.circle.badge.checkmark") { model.make(item, attendance: .excused) }
            .disabled(!model.canMark(item, .excused))
        Divider()
        Button(.sessionsCancelled, systemImage: "calendar.badge.minus") { model.make(item, kind: .cancelled) }
        Divider()
        Button(.commonEditEllipsis, systemImage: "pencil") {
            sheets.present(.session(SessionSheetRequest(course: item.courseId, start: item.suggestion.date)))
        }
        if let editTimes {
            Divider()
            Button(.sessionsClassTimesChangeEllipsis, systemImage: "clock", action: editTimes)
        }
    }
}
