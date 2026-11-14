import FolioActions
import FolioDomain
import FolioLMS
import Foundation

extension Workspace {
    var lmsInbox: LMSInbox {
        guard let snapshot = lms.snapshot else { return LMSInbox() }
        return LMSInbox.build(snapshot, settings: settings.lms, courses: courses.map(\.file), now: now)
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
        guard let snapshot = await lms.sync() else { return }
        let new = settings.lms.unseen(in: snapshot).map(\.id)
        guard !new.isEmpty else { return }
        run(LMSSeen(classrooms: new, items: new.flatMap(snapshot.current(in:)).map(\.description)))
    }

    func accept(_ proposals: [LMSProposal], into course: UUID) async {
        var items: [LMSAcceptItem] = []
        for p in proposals {
            switch p.item {
            case .assignment(let a): items.append(LMSAcceptItem(key: p.key.description, title: a.title, due: a.due))
            case .notice: items.append(LMSAcceptItem(key: p.key.description))
            case .file(let f):
                do {
                    if let url = try await lms.download(f) { items.append(LMSAcceptItem(key: p.key.description, file: url.path)) }
                } catch {
                    self.error = String(localized: .lmsDownloadFailed(f.title, error.localizedDescription))
                    return
                }
            }
        }
        if !items.isEmpty { run(LMSAccept(course: course, items: items)) }
    }

    func dismiss(_ proposals: [LMSProposal]) {
        run(LMSMark(keys: proposals.map(\.key.description), handled: true))
    }

    func propose(again proposals: [LMSProposal]) {
        run(LMSMark(keys: proposals.map(\.key.description), handled: false))
    }
}
