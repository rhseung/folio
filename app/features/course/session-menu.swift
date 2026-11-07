import FolioDomain
import SwiftUI

/// A saved class's menu, the same on every screen. What needs a sheet or a dialog of the host (editing, deleting)
/// shows only where the host passes it; elsewhere 회차에서 보기 leads to the page that has them. A recording is a page
/// of its own, so it plays from any of them.
struct SessionMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openURL) private var openURL
    @Environment(\.openLink) private var openLink
    let courseId: UUID
    let sessionId: UUID
    let openNote: (UUID) -> Void
    var showSessions: (() -> Void)?
    var edit: (() -> Void)?
    /// The class's wrap-up: progress, units, note, attendance.
    var wrapUp: (() -> Void)?
    var remove: (() -> Void)?

    var body: some View {
        let model = SessionMenuModel(workspace: workspace, courseId: courseId)
        if let session = model.session(sessionId) {
            if let link = model.link(of: session) {
                Button(.sessionsJoinOnline, systemImage: "video") { JoinOnlineButton.join(link, openURL) }
                Divider()
            }
            Button(model.noteLabel(.rough, of: session), systemImage: "pencil.line") { open(.rough, session, model) }
            Button(model.noteLabel(.review, of: session), systemImage: "square.and.pencil") { open(.review, session, model) }
            if session.reviewNoteId != nil {
                if session.reviewNoteUnfinished {
                    Button(.courseReviewNoteFinish, systemImage: "checkmark.circle") { model.setReviewNoteUnfinished(false, of: session) }
                } else {
                    Button(.courseReviewNoteReopen, systemImage: "arrow.uturn.backward") { model.setReviewNoteUnfinished(true, of: session) }
                }
            }
            Toggle(isOn: Binding(get: { session.skipsReview }, set: { model.setSkipsReview($0, of: session) })) {
                Label(.sessionsSkipsReview, systemImage: "forward")
            }
            // Also ahead of the class, for an absence known in advance; it counts toward the caps once the class starts.
            if model.takesAttendance(session) {
                Picker(selection: Binding(get: { model.attendance(of: session) }, set: { model.setAttendance($0, of: session) })) {
                    ForEach(AttendanceState.steps, id: \.value) { Text($0.label).tag($0.value) }
                } label: {
                    Label(.sessionsAttendance, systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            Divider()
            Button(.sessionsRecord, systemImage: "record.circle") { model.record(session) }.disabled(model.isRecording)
            ForEach(Array(model.recordings(of: session).enumerated()), id: \.element.id) { i, r in
                Button(model.playLabel(i, r), systemImage: "play") { openLink(AppLink(.recording, r.id), course: courseId) }
            }
            Divider()
            if let edit { Button(.commonEditEllipsis, systemImage: "pencil", action: edit) }
            if let wrapUp, !session.isCancelled { Button(.wrapUpEllipsis, systemImage: "checklist", action: wrapUp) }
            Toggle(isOn: Binding(get: { session.isCancelled }, set: { model.setCancelled($0, of: session) })) {
                Label(.sessionsCancelled, systemImage: "calendar.badge.minus")
            }
            if let remove {
                Divider()
                Button(.sessionsRemoveSessionEllipsis, systemImage: "trash", role: .destructive, action: remove)
            }
            if let showSessions {
                Divider()
                Button(.courseShowSessions, systemImage: "calendar", action: showSessions)
            }
            LinkMenu(link: AppLink(.session, sessionId), course: courseId, trailing: true)
        }
    }

    func open(_ kind: NoteKind, _ session: Session, _ model: SessionMenuModel) {
        if let id = model.note(kind, of: session) { openNote(id) }
    }
}

/// A class the timetable holds but no session stands for yet. Anything done to it makes the session first, so a 휴강
/// or an absence known weeks ahead has something to hang on. With `primary`, led by the row's own button, for the
/// row's context menu.
struct SuggestedSessionItems: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openURL) private var openURL
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
        Button(.sessionsCancelled, systemImage: "calendar.badge.minus") { model.make(item, cancelled: true) }
        if let editTimes {
            Divider()
            Button(.sessionsClassTimesChangeEllipsis, systemImage: "clock", action: editTimes)
        }
    }
}
