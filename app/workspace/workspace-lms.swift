import FolioActions
import FolioDomain
import FolioLMS
import Foundation

extension Workspace {
    var lmsInbox: LMSInbox {
        guard let snapshot = lms.snapshot else { return LMSInbox() }
        return LMSInbox.build(
            snapshot, settings: settings.lms, courses: courses.map(\.file), now: now,
            soonDays: settings.urgency.assignmentSoonDays)
    }

    // 과목 열 끝의 LMS 강의실 행이다. 받을 때 이 과목을 고른 강의실만 보이고, 수는 그 강의실의 처리할 것이다.
    func lmsRooms(of course: UUID) -> [(classroom: LMSClassroom, waiting: Int)] {
        guard let snapshot = lms.snapshot else { return [] }
        let rooms = settings.lms.classrooms(of: course, in: snapshot)
        guard !rooms.isEmpty else { return [] }
        let board = proposalBoard
        return rooms.map { ($0, board.room($0.id)?.proposals.count ?? 0) }
    }

    var lmsLastSync: String {
        guard let at = lms.snapshot?.at, at > .distantPast else { return String(localized: .lmsNeverSynced) }
        return String(localized: .lmsLastSync(lmsTime(at)))
    }

    func lmsTime(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day: Date.FormatStyle =
            sameYear ? .dateTime.month().day().weekday(.abbreviated) : .dateTime.year().month().day().weekday(.abbreviated)
        return date.formatted(day.hour().minute())
    }

    // 처음 보는 강의실은 지금 있는 자료와 공지를 숨긴다. 그래야 새 학기에 오래된 글 수백 개를 제안하지 않는다. 남은 과제는
    // 계속 제안한다.
    func syncLMS() async {
        let (known, files, at) = (settings.lms, courses.map(\.file), now)
        guard
            let snapshot = await lms.sync(attachments: {
                LMSInbox.attachmentsToRead($0, settings: known, courses: files, now: at)
            })
        else { return }
        let new = settings.lms.unseen(in: snapshot).map(\.id)
        guard !new.isEmpty else { return }
        run(LMSSeen(classrooms: new, items: new.flatMap(snapshot.current(in:)).map(\.description)))
    }
}
