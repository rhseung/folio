import Foundation

// 이미 받은 과제가 LMS와 다른 것이다. 받은 과제의 `lmsId`로 찾으므로 강의실의 과목을 몰라도 된다. 하나씩 승인하거나
// 무시하고, 한 번에 맞추는 단추는 두지 않는다.
public struct LMSDifference: Hashable, Sendable {
    public enum Change: Hashable, Sendable {
        // Folio에서는 냈는데 LMS 마감이 지나도록 LMS에는 내지 않았다.
        case unsubmitted
        case due(folio: Date?, lms: Date)
        // 과제 폴더에 없는 LMS 첨부다. 받은 뒤 과제 페이지에 더 올라온 문제 파일이 여기에 든다.
        case attachments([LMSAttachment])
    }

    public var lms: LMSAssignment
    public var course: UUID
    public var assignment: UUID
    public var change: Change

    public init(lms: LMSAssignment, course: UUID, assignment: UUID, change: Change) {
        self.lms = lms
        self.course = course
        self.assignment = assignment
        self.change = change
    }

    public var key: LMSKey {
        switch change {
        case .unsubmitted: .init(kind: .unsubmitted, id: lms.id)
        case .due(_, let date): .init(kind: .due, id: lms.id, stamp: Self.minute(date))
        case .attachments: .init(kind: .attachments, id: lms.id, stamp: lms.attachments?.count ?? 0)
        }
    }

    // LMS 표는 분까지 적으므로 분 단위로 비교한다.
    public static func minute(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 60).rounded(.down)) }

    // 마감이 지난 과제는 마감을 고쳐도 할 일이 바뀌지 않으므로, LMS 마감이 지나지 않았을 때만 다르다고 본다.
    // 첨부는 과제 폴더(`files`)에 같은 이름의 파일이 있으면 받은 것으로 본다. 과제 폴더 안의 이름은 바꾸지 않으므로 이름으로
    // 맞출 수 있다. 첨부를 읽지 않은 과제(`attachments == nil`)는 비교하지 않는다.
    static func find(_ lms: LMSAssignment, in a: Assignment, files: [Material] = [], course: UUID, now: Date) -> [LMSDifference] {
        var out: [LMSDifference] = []
        // LMS에서 낸 과제는 제안하지 않고 동기화가 바로 제출함으로 바꾼다(`LMSInbox.submissions`).
        if !lms.submitted, a.status == .submitted, let due = lms.due, due < now {
            out.append(.init(lms: lms, course: course, assignment: a.id, change: .unsubmitted))
        }
        if a.repeats == nil, let due = lms.due, due >= now, a.due.map(minute) != minute(due) {
            out.append(.init(lms: lms, course: course, assignment: a.id, change: .due(folio: a.due, lms: due)))
        }
        let names = Set(files.map { ($0.path as NSString).lastPathComponent })
        let new = (lms.attachments ?? []).filter { !names.contains($0.name) }
        if !new.isEmpty { out.append(.init(lms: lms, course: course, assignment: a.id, change: .attachments(new))) }
        return out
    }
}
