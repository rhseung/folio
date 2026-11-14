import Foundation

extension Session {
    public func isOver(at now: Date, schedule: [ClassTime], classMinutes: Int, calendar: Calendar) -> Bool {
        now >= expectedEnd(schedule: schedule, classMinutes: classMinutes, calendar: calendar)
    }
}

extension CourseFile {
    public func review(of session: Session) -> ClassReview? {
        if session.reviewNoteId != nil { return session.reviewNoteUnfinished ? .writing : .written }
        guard course.reviews != false, !session.isCancelled else { return nil }
        return session.skipsReview ? .notNeeded : .needed
    }

    public func recordings(of session: Session) -> [Recording] {
        recordings.filter { $0.sessionId == session.id }
    }

    public func commands(for session: Session, at now: Date, host: MenuHost, classMinutes: Int, calendar: Calendar) -> [SessionMenuCommand]
    {
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

    public func sections(of session: Session?, kind: Session.Kind, start: Date, at now: Date, takesAttendance: Bool) -> [SessionSection] {
        if kind == .cancelled { return [.info] }
        let attendance: [SessionSection] = takesAttendance ? [.attendance] : []
        guard session != nil else { return [.info, .units] + attendance }
        guard start <= now else { return [.info, .units, .notes] + attendance }
        return (lectureFiles.isEmpty ? [] : [.progress]) + [.units, .notes] + attendance + [.info]
    }
}
