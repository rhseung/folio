import FolioActions
import FolioDomain
import FolioLMS
import Foundation

extension Workspace {
    var lmsInbox: LMSInbox {
        guard let snapshot = lms.snapshot else { return LMSInbox() }
        return LMSInbox.build(snapshot, settings: settings.lms, courses: courses.map(\.file), now: now)
    }

    /// A classroom seen for the first time gets its files and notices of now marked handled, so a new term doesn't
    /// propose hundreds of old posts; its open assignments are still proposed.
    func syncLMS() async {
        guard let snapshot = await lms.sync() else { return }
        let new = settings.lms.unseen(in: snapshot).map(\.id)
        guard !new.isEmpty else { return }
        run(LMSSeen(classrooms: new, items: new.flatMap(snapshot.current(in:)).map(\.description)))
    }

    /// Files are downloaded before the one action that takes them all; one the LMS only shows in its viewer is left
    /// out and stays proposed, now marked so.
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
}
