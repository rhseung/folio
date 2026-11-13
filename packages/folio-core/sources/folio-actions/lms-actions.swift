import FolioDomain
import FolioStorage
import Foundation

// No classroom is tied to a course (one course can have two, and some are no course at all), so this only records
// that a classroom was seen and what it held then.
@Action("lms seen", "처음 본 LMS 강의실을 기록하고 지금 있는 항목을 처리한 것으로 남기기", discussion: """
        강의실을 처음 볼 때 그 강의실에 이미 있는 파일과 공지를 --items로 넘겨, 그 뒤에 올라온 것만 제안한다.
        강의실을 과목에 잇지 않는다. 제안은 받을 때마다 과목을 고른다.
        """,
        done: "LMS 강의실 {classrooms}을(를) 기록했습니다",
        examples: ["folio lms seen 27967 28011 --items file:139109 --items notice:23464"],
        phrases: ["LMS 강의실 기록", "LMS 새 강의실"])
public struct LMSSeen {
    /// LMS 강의실 번호(course/view.php?id=)
    @Arg var classrooms: [Int]
    /// 처리한 것으로 남길 항목. file:139109, notice:23464 꼴
    var items: [String] = []

    public func run(_ ctx: ActionContext) throws {
        guard !classrooms.isEmpty else { throw ActionError.input(String(localized: .errorLmsNoClassrooms)) }
        let keys = try items.map { text in
            guard let key = LMSKey(text) else { throw ActionError.input(String(localized: .errorLmsKey(text))) }
            return key
        }
        try ctx.editSettings { s in
            s.lms.know(classrooms)
            s.lms.mark(keys, handled: true)
        }
    }
}

@Action("lms mark", "LMS 항목을 처리한 것으로 남겨 다시 제안하지 않기, --off면 다시 제안하기",
        done: "LMS 항목 {keys}을(를) 표시했습니다",
        examples: ["folio lms mark notice:23464 file:139109", "folio lms mark notice:23464 --off"],
        phrases: ["LMS 제안 무시", "LMS 공지 숨기기"])
public struct LMSMark {
    /// 항목. assignment:139941, file:139109, notice:23464 꼴
    @Arg var keys: [String]
    /// 다시 제안하기
    @Off("off") var handled = true

    public func run(_ ctx: ActionContext) throws {
        guard !keys.isEmpty else { throw ActionError.input(String(localized: .errorLmsNoKeys)) }
        let parsed = try keys.map { text in
            guard let key = LMSKey(text) else { throw ActionError.input(String(localized: .errorLmsKey(text))) }
            return key
        }
        try ctx.editSettings { $0.lms.mark(parsed, handled: handled) }
    }
}

/// One LMS proposal the user accepted. A file carries the path it was downloaded to; one the LMS shows only in its
/// viewer has none and cannot be accepted, only opened or dismissed.
public struct LMSAcceptItem: Codable, Sendable, Hashable {
    /// assignment:139950, file:139200, notice:23464
    public var key: String
    public var title: String?
    public var due: Date?
    public var file: String?

    public init(key: String, title: String? = nil, due: Date? = nil, file: String? = nil) {
        (self.key, self.title, self.due, self.file) = (key, title, due, file)
    }
}

// "모두 추가" on a course's proposals is this one action, so it asks once and stops before writing anything when one
// item is refused.
@Action("lms accept", "LMS 제안을 과목에 받기. 과제는 과제로 더하고, 받은 파일은 Lectures로 가져오고, 모두 처리한 것으로 남긴다",
        discussion: "항목 파일은 [{\"key\":\"assignment:139950\",\"title\":\"HW5\",\"due\":\"2026-11-20T14:55:00Z\"}, {\"key\":\"file:139200\",\"file\":\"/tmp/05_Matchings.pdf\"}, {\"key\":\"notice:23464\"}] 꼴이다.",
        effect: .creates, done: "{course}에 LMS 항목을 받았습니다",
        phrases: ["LMS 과제 추가", "LMS 자료 받기", "LMS 제안 모두 추가"])
public struct LMSAccept {
    /// 과목
    @Arg var course: Course.ID
    /// 받을 항목
    @FromFile("items.json") var items: [LMSAcceptItem]

    public func run(_ ctx: ActionContext) throws {
        guard !items.isEmpty else { throw ActionError.input(String(localized: .errorLmsNoKeys)) }
        let file = try ctx.file(course)
        var keys: [LMSKey] = []
        var assignments: [(id: Int, title: String, due: Date?)] = []
        var downloads: [ImportItem] = []
        for item in items {
            guard let key = LMSKey(item.key) else { throw ActionError.input(String(localized: .errorLmsKey(item.key))) }
            keys.append(key)
            switch key.kind {
            case .assignment:
                guard let title = item.title, !title.isEmpty else { throw ActionError.rule(String(localized: .errorAssignmentTitleEmpty)) }
                if let same = file.assignments.first(where: { $0.lmsId == key.id }) {
                    throw ActionError.rule(String(localized: .errorLmsAssignmentAdded(same.title)))
                }
                assignments.append((key.id, title, item.due))
            case .file:
                guard let path = item.file else { throw ActionError.rule(String(localized: .errorLmsFileMissing(item.key))) }
                downloads.append(ImportItem(file: path, folder: CourseFolder.lectures.rawValue))
            case .notice:
                break
            }
        }
        if !downloads.isEmpty {
            for d in downloads where !FileManager.default.fileExists(atPath: d.file) {
                throw ActionError.notFound(String(localized: .errorMaterialImportMissing(d.file)))
            }
        }
        for a in assignments {
            try AssignmentAdd(id: UUID(), course: course, title: a.title, due: a.due, repeats: nil, lms: a.id).run(ctx)
        }
        if !downloads.isEmpty { try MaterialImport(course: course, items: downloads).run(ctx) }
        try ctx.editSettings { $0.lms.mark(keys, handled: true) }
    }
}
