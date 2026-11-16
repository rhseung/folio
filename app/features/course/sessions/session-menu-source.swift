import FolioActions
import FolioDomain
import SwiftUI

@MainActor
struct SessionMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let session: Session
    let host: MenuHost
    let now: Date
    let openNote: (UUID) -> Void
    let openLink: OpenLinkAction
    let openURL: OpenURLAction
    let sheets: ItemSheetsAction

    private var file: CourseFile? { workspace.course(courseId)?.file }
    private var link: AppLink { AppLink(.session, session.id) }

    var commands: [SessionMenuCommand] {
        file?.commands(for: session, at: now, host: host, classMinutes: workspace.settings.classMinutes, calendar: workspace.calendar) ?? []
    }

    func row(_ command: SessionMenuCommand) -> MenuRow {
        let row = { (title: String, symbol: String, kind: MenuRow.Kind) in
            MenuRow(id: command, group: command.group, title: title, symbol: symbol, kind: kind)
        }
        switch command {
        case .open:
            return row(String(localized: .commonOpen), "arrow.right.circle", .action { openLink(link, course: courseId) })
        case .join:
            return row(
                String(localized: .sessionsJoinOnline), "video",
                .action {
                    if let file, let url = session.link(schedule: file.course.schedule, calendar: workspace.calendar) {
                        JoinOnlineButton.join(url, openURL)
                    }
                })
        case .openNote(let kind):
            return row(
                String(localized: kind == .rough ? .sessionsOpenRoughNote : .sessionsOpenReviewNote), "doc.text", .action { open(kind) })
        case .makeReviewNote:
            return row(String(localized: .sessionsMakeReviewNote), "square.and.pencil", .action { open(.review) })
        case .play(let id):
            return row(String(localized: .sessionsPlayRecordingOne(duration(id))), "play", .action { play(id) })
        case .recordings(let ids):
            return row(
                String(localized: .sessionsRecordingShort), "waveform",
                .submenu(
                    ids.enumerated().map { i, id in
                        MenuRow.Leaf(id: id, title: String(localized: .sessionsRecordingNumbered(i + 1, duration(id))), symbol: "play") {
                            play(id)
                        }
                    }))
        case .record:
            var r = row(String(localized: .sessionsRecord), "record.circle", .action { workspace.record(session.id, in: courseId) })
            r.disabled = workspace.recorder.isActive
            return r
        case .review(let review):
            let title = String(localized: review == .needed || review == .notNeeded ? .sessionsSkipsReview : .sessionsReviewWritten)
            return row(
                title, review.reviewUnfinished == nil ? "forward" : "checkmark.circle",
                .check(review.isChecked) { _ in setReview(review.toggled) })
        case .edit:
            return row(
                String(localized: .commonEditEllipsis), "pencil",
                .action {
                    sheets.present(.session(SessionSheetRequest(course: courseId, session: session.id)))
                })
        case .unlink(let unit):
            return row(
                String(localized: .unitsUnlinkSession), "link.badge.minus",
                .action {
                    workspace.run(UnitLink(course: courseId, unit: unit, sessions: [session.id], linked: false))
                })
        case .share:
            return row(String(localized: .menuShare), "square.and.arrow.up", .share(link, course: courseId))
        case .remove:
            var r = row(
                String(localized: .commonDeleteEllipsis), "trash",
                .action {
                    sheets.confirm(workspace.ask(SessionRemove(course: courseId, sessions: [session.id]), button: .sessionsRemove))
                })
            r.role = .destructive
            return r
        }
    }

    private func open(_ kind: NoteKind) {
        if let id = workspace.note(kind, of: session.id, in: courseId) { openNote(id) }
    }

    private func play(_ id: UUID) { openLink(AppLink(.recording, id), course: courseId) }

    private func duration(_ id: UUID) -> String {
        RecordingTime.label(file?.recordings.first { $0.id == id }?.duration ?? 0)
    }

    func setReview(_ review: ClassReview) {
        workspace.run(
            SessionSet(
                course: courseId, session: session.id,
                skipsReview: review.skipsReview.map(Patch.set) ?? .keep,
                reviewUnfinished: review.reviewUnfinished.map(Patch.set) ?? .keep))
    }
}
