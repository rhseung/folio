import FolioDomain
import Foundation
import Security

public enum LMSSync {
    // `attachments`는 다 읽은 목록에서 첨부를 읽을 과제를 고른다. 고른 과제마다 과제 페이지를 하나 더 읽는다.
    public static func read(
        _ client: LMSClient, at now: Date, attachments: @Sendable (LMSSnapshot) -> [LMSAssignment] = { _ in [] }
    ) async throws -> LMSSnapshot {
        var snapshot = LMSSnapshot(at: now, classrooms: try LMSPages.classrooms(await client.page("/")))
        for room in snapshot.classrooms {
            snapshot.merge(try await classroom(client, room.id), in: room.id)
        }
        let wanted = Set(attachments(snapshot).map(\.id))
        for i in snapshot.assignments.indices where wanted.contains(snapshot.assignments[i].id) {
            let page = try await client.page("/mod/assign/view.php?id=\(snapshot.assignments[i].id)")
            snapshot.assignments[i].attachments = try LMSPages.attachments(page)
        }
        return snapshot
    }

    public static func classroom(_ client: LMSClient, _ id: Int) async throws -> LMSSnapshot {
        LMSSnapshot(
            at: .now,
            assignments: try LMSPages.assignments(await client.page("/mod/assign/index.php?id=\(id)"), classroom: id),
            files: try LMSPages.files(await client.page("/mod/ubfile/index.php?id=\(id)"), classroom: id),
            notices: try LMSPages.notices(await client.page("/mod/ubboard/my.php?mc=\(id)"), classroom: id))
    }
}
