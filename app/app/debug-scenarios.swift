#if DEBUG
import FolioActions
import FolioDomain
import FolioFixtures
import FolioLMS
import FolioStorage
import Foundation

extension Workspace {
    /// A fresh copy of the scenario with the clock pinned to its moment, for previews and offscreen renders.
    static func scenario(_ scenario: Scenario) throws -> Workspace {
        let url = try scenario.copyToTemp()
        // With FOLIO_GIST set, open() leaves the remembered folder alone, so a preview never repoints the real app or `folio`.
        setenv(environmentKey, url.path(percentEncoded: false), 1)
        let workspace = Workspace()
        workspace.pinnedNow = scenario.now
        workspace.calendar = Scenario.calendar
        // Before opening, whose reload recovers leftovers: left unset, the first use stops the run (LocalFolders).
        workspace.pendingRecordings = PendingRecordings(url: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        workspace.open(url, remember: false)
        workspace.releaseNotes = ReleaseNotes(source: ReleaseList(list: ReleaseList.sample), current: ReleaseList.sample[0].version, prompts: false)
        let lms = LMSSnapshot.sample(at: scenario.now)
        workspace.lms = LMSConnection(source: FixedLMS(snapshot: lms), logins: MemoryLogins(LMSCredentials(username: "20260000", password: "-")))
        // Known already, so the proposals show; a first sync would have marked them handled.
        workspace.run(LMSSeen(classrooms: lms.classrooms.map(\.id), items: []))
        return workspace
    }
}

extension LMSSnapshot {
    /// Made-up classrooms for previews and renders: two of one course, one that is no course, one with nothing new.
    static func sample(at now: Date) -> LMSSnapshot {
        let day: TimeInterval = 86_400
        return LMSSnapshot(
            at: now.addingTimeInterval(-12 * 60),
            classrooms: [LMSClassroom(id: 27967, title: "그래프 이론 [01분반]", kind: "교과", professors: "김교수"),
                         LMSClassroom(id: 27968, title: "그래프 이론 [실습]", kind: "교과"),
                         LMSClassroom(id: 28011, title: "2026 가을 소방안전교육", kind: "비교과"),
                         LMSClassroom(id: 28020, title: "선형대수학과 응용 (01분반)", kind: "교과")],
            assignments: [LMSAssignment(id: 139950, classroom: 27967, title: "Homework Set #5", due: now.addingTimeInterval(3 * day)),
                          LMSAssignment(id: 139951, classroom: 27968, title: "Lab 4 보고서", due: now.addingTimeInterval(6 * day)),
                          LMSAssignment(id: 140002, classroom: 28011, title: "소방안전교육 이수 확인", due: now.addingTimeInterval(10 * day))],
            files: [LMSFile(id: 139200, classroom: 27967, title: "Matchings and Flows", week: "9주차 [10월26일 - 11월1일]"),
                    LMSFile(id: 139201, classroom: 27968, title: "Lab 4 매뉴얼", week: "9주차 [10월26일 - 11월1일]")],
            notices: [LMSNotice(id: 23464, board: 9, classroom: 27967, title: "중간고사 성적 공개 안내", author: "김교수",
                                posted: now.addingTimeInterval(-day)),
                      LMSNotice(id: 23470, board: 12, classroom: 28011, title: "온라인 교육 수강 방법", author: "학생지원팀",
                                posted: now.addingTimeInterval(-2 * day))])
    }
}
#endif
