#if DEBUG
import FolioActions
import FolioDomain
import FolioFixtures
import FolioLMS
import FolioStorage
import Foundation

extension Workspace {
    static func scenario(_ scenario: Scenario) throws -> Workspace {
        let url = try scenario.copyToTemp()
        setenv(environmentKey, url.path(percentEncoded: false), 1)
        let workspace = Workspace()
        workspace.pinnedNow = scenario.now
        workspace.calendar = Scenario.calendar
        // `open()`이 다시 읽으면서 남은 녹음을 복구하므로 그 전에 설정한다. 설정하지 않으면 처음 쓸 때 실행이
        // 멈춘다(`LocalFolders`).
        workspace.pendingRecordings = PendingRecordings(
            url: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        workspace.open(url, remember: false)
        workspace.releaseNotes = ReleaseNotes(
            source: ReleaseList(list: ReleaseList.sample), current: ReleaseList.sample[0].version, prompts: false)
        let lms = LMSSnapshot.sample(at: scenario.now)
        workspace.lms = LMSConnection(
            source: FixedLMS(snapshot: lms), logins: MemoryLogins(LMSCredentials(username: "20260000", password: "-")))
        workspace.run(LMSSeen(classrooms: lms.classrooms.map(\.id), items: LMSSnapshot.sampleHandled))
        return workspace
    }
}

extension LMSSnapshot {
    static let sampleHandled = ["file:139100", "file:139101", "notice:23300"]

    static func sample(at now: Date) -> LMSSnapshot {
        let day: TimeInterval = 86_400
        return LMSSnapshot(
            at: now.addingTimeInterval(-12 * 60),
            classrooms: [
                LMSClassroom(id: 27967, title: "그래프 이론 [01분반]", kind: "교과", professors: "김교수"),
                LMSClassroom(id: 27968, title: "그래프 이론 [실습]", kind: "교과"),
                LMSClassroom(id: 28011, title: "2026 가을 소방안전교육", kind: "비교과"),
                LMSClassroom(id: 28020, title: "선형대수학과 응용 (01분반)", kind: "교과"),
            ],
            assignments: [
                LMSAssignment(id: 139950, classroom: 27967, title: "Homework Set #5", due: now.addingTimeInterval(3 * day)),
                LMSAssignment(id: 139951, classroom: 27968, title: "Lab 4 보고서", due: now.addingTimeInterval(10 * day)),
                LMSAssignment(id: 140002, classroom: 28011, title: "소방안전교육 이수 확인", due: now.addingTimeInterval(2 * 3600)),
            ],
            files: [
                LMSFile(id: 139100, classroom: 27967, title: "Introduction", week: "1주차 [9월1일 - 9월7일]"),
                LMSFile(id: 139101, classroom: 27967, title: "Trees", week: "2주차 [9월8일 - 9월14일]"),
                LMSFile(id: 139200, classroom: 27967, title: "Matchings and Flows", week: "9주차 [10월26일 - 11월1일]"),
                LMSFile(id: 139201, classroom: 27968, title: "Lab 4 매뉴얼", week: "9주차 [10월26일 - 11월1일]"),
            ],
            notices: [
                LMSNotice(
                    id: 23300, board: 15, classroom: 28020, title: "강의실 이용 안내", author: "이교수",
                    posted: now.addingTimeInterval(-60 * day)),
                LMSNotice(
                    id: 23464, board: 9, classroom: 27967, title: "중간고사 성적 공개 안내", author: "김교수",
                    posted: now.addingTimeInterval(-day)),
                LMSNotice(
                    id: 23470, board: 12, classroom: 28011, title: "온라인 교육 수강 방법", author: "학생지원팀",
                    posted: now.addingTimeInterval(-2 * day)),
            ])
    }
}
#endif
