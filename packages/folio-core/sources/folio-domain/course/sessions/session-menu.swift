import Foundation

/// Where a class's review stands, as its menu checks it and its sheet picks it. Two values without a note (owed or
/// not), two with one (being written or written), so the menu needs a single check row whichever the class has.
public enum ClassReview: Hashable, Sendable, CaseIterable {
    case needed, notNeeded, writing, written

    /// The values the class can move between: a note's existence isn't a choice here, it is made or linked.
    public var choices: [ClassReview] {
        switch self {
        case .needed, .notNeeded: [.needed, .notNeeded]
        case .writing, .written: [.writing, .written]
        }
    }

    /// The menu's one check row names the checked value: 복습 필요 없음 without a note, 작성 완료 with one.
    public var isChecked: Bool { self == .notNeeded || self == .written }

    public var toggled: ClassReview {
        switch self {
        case .needed: .notNeeded
        case .notNeeded: .needed
        case .writing: .written
        case .written: .writing
        }
    }

    /// The session flag a move to this value writes. The other flag is left alone.
    public var skipsReview: Bool? {
        switch self {
        case .needed: false
        case .notNeeded: true
        case .writing, .written: nil
        }
    }

    public var reviewUnfinished: Bool? {
        switch self {
        case .writing: true
        case .written: false
        case .needed, .notNeeded: nil
        }
    }
}

/// What a saved class's menu can hold. Rows for things the class doesn't have are left out rather than greyed: no
/// open-note row without the note, no recording row without a recording.
public enum SessionMenuCommand: ItemCommand {
    /// The class on its own screen, from anywhere else.
    case open
    case join
    case openNote(NoteKind)
    case makeReviewNote
    case play(UUID)
    /// Several recordings: a submenu, one row each.
    case recordings([UUID])
    case record
    /// The one review row, holding the value it toggles from.
    case review(ClassReview)
    case edit
    case unlink(unit: UUID)
    case share
    case remove

    // No default: a new command doesn't compile until it says where it goes.
    public var group: MenuGroup {
        switch self {
        case .open, .join, .openNote, .makeReviewNote, .play, .recordings: .open
        case .record: .start
        case .review: .state
        case .edit: .edit
        case .unlink: .arrange
        case .share: .share
        case .remove: .remove
        }
    }
}

/// The groups of a class's one sheet, which edits everything a class has (#403).
public enum SessionSection: String, CaseIterable, Sendable {
    case progress, units, notes, attendance, info
}

extension Session {
    /// Before its end the class is still to be held, so its menu offers what holding it takes; after, what follows it.
    public func isOver(at now: Date, schedule: [ClassTime], classMinutes: Int, calendar: Calendar) -> Bool {
        now >= expectedEnd(schedule: schedule, classMinutes: classMinutes, calendar: calendar)
    }
}

extension CourseFile {
    /// Nil when nothing about review is asked of the class: it didn't happen, or the course is left out of review.
    /// A note made anyway still has its state.
    public func review(of session: Session) -> ClassReview? {
        if session.reviewNoteId != nil { return session.reviewNoteUnfinished ? .writing : .written }
        guard course.reviews != false, !session.isCancelled else { return nil }
        return session.skipsReview ? .notNeeded : .needed
    }

    public func recordings(of session: Session) -> [Recording] {
        recordings.filter { $0.sessionId == session.id }
    }

    /// A class's menu at `now`, in menu order. Ahead and under way: joining, the rough note, recording. Once over: the
    /// notes, the review check and the recordings. Editing, sharing and deleting always.
    public func commands(for session: Session, at now: Date, host: MenuHost, classMinutes: Int, calendar: Calendar) -> [SessionMenuCommand] {
        var commands: [SessionMenuCommand] = []
        if host.opensItem { commands.append(.open) }
        let held = !session.isCancelled
        if session.isOver(at: now, schedule: course.schedule, classMinutes: classMinutes, calendar: calendar) {
            if session.roughNoteId != nil { commands.append(.openNote(.rough)) }
            if let review = review(of: session) {
                commands.append(session.reviewNoteId == nil ? .makeReviewNote : .openNote(.review))
                commands.append(.review(review))
            }
            let recorded = recordings(of: session).sorted { $0.createdAt < $1.createdAt }.map(\.id)
            if recorded.count == 1 { commands.append(.play(recorded[0])) }
            if recorded.count > 1 { commands.append(.recordings(recorded)) }
        } else {
            if held, session.link(schedule: course.schedule, calendar: calendar) != nil { commands.append(.join) }
            if session.roughNoteId != nil { commands.append(.openNote(.rough)) }
            if held { commands.append(.record) }
        }

        commands.append(.edit)
        if case .unit(let unit) = host, session.unitIds.contains(unit) { commands.append(.unlink(unit: unit)) }
        commands += [.share, .remove]
        return commands.inMenuOrder()
    }

    /// The sheet's groups for a class of `kind` starting at `start`, or one being added (`session` nil). Once the class
    /// has begun the sheet asks what it covered first and its time last; ahead of it, the time comes first and there is
    /// no progress yet. A cancelled class has only its time and kind.
    public func sections(of session: Session?, kind: Session.Kind, start: Date, at now: Date, takesAttendance: Bool) -> [SessionSection] {
        if kind == .cancelled { return [.info] }
        let attendance: [SessionSection] = takesAttendance ? [.attendance] : []
        guard session != nil else { return [.info, .units] + attendance }
        guard start <= now else { return [.info, .units, .notes] + attendance }
        return (lectureFiles.isEmpty ? [] : [.progress]) + [.units, .notes] + attendance + [.info]
    }
}
