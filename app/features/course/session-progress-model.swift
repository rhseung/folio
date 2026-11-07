import FolioActions
import FolioDomain
import Foundation
import Observation

/// How far one class went in its lecture files, asked when its recording stops or from the class's menu. Rows start
/// from `CourseFile.suggestedProgress`; saving writes every kept row in one action.
@MainActor @Observable
final class SessionProgressModel {
    struct Row: Identifiable, Equatable {
        let id: UUID
        var included = true
        var first: Int?
        var last: Int?
    }

    let workspace: Workspace
    let courseId: UUID
    let sessionId: UUID
    let viewed: [SessionMaterial]
    private(set) var rows: [Row] = []
    private(set) var pageCounts: [UUID: Int] = [:]
    /// Once a field is touched, counts arriving late no longer redo the suggestion under the user's hands.
    private var edited = false

    init(workspace: Workspace, course: UUID, session: UUID, viewed: [SessionMaterial] = []) {
        self.workspace = workspace
        courseId = course
        sessionId = session
        self.viewed = viewed
        suggest()
    }

    private var file: CourseFile? { workspace.course(courseId)?.file }
    private var session: Session? { file?.sessions.first { $0.id == sessionId } }

    private func suggest() {
        guard let file, let session else { return }
        rows = file.suggestedProgress(for: session, viewed: viewed, pageCounts: pageCounts)
            .map { Row(id: $0.materialId, first: $0.firstPage, last: $0.lastPage) }
    }

    /// Counts tell where a file ends: the first page stays within it, and a finished file hands over to the next.
    func load() async {
        guard let file else { return }
        var counts: [UUID: Int] = [:]
        // Only the files listed: reading every lecture would download each from iCloud.
        for m in file.materials where rows.contains(where: { $0.id == m.id }) {
            if let n = await workspace.pageCount(of: m, course: courseId) { counts[m.id] = n }
        }
        pageCounts = counts
        if !edited { suggest() }
    }

    var title: String {
        guard let file, let session else { return String(localized: .sessionsProgressTitle) }
        return String(localized: .sessionsProgressTitleOf(file.day(of: session, calendar: workspace.calendar)))
    }

    func name(_ id: UUID) -> String {
        file?.materials.first { $0.id == id }.map { ($0.path as NSString).lastPathComponent } ?? ""
    }

    /// Where the numbers came from, under the file's name: what the last class reached, what the recording saw,
    /// and how long the file is.
    func detail(_ id: UUID) -> String {
        guard let file, let session else { return "" }
        var parts: [String] = []
        if let resume = file.resumePage(of: id, for: session) { parts.append(String(localized: .sessionsProgressLastClass(resume - 1))) }
        if let seen = viewed.first(where: { $0.materialId == id }), let pages = seen.pages {
            parts.append(String(localized: .sessionsProgressRecorded(pages.lowerBound, pages.upperBound)))
        }
        if let count = pageCounts[id] { parts.append(String(localized: .sessionsProgressPageCount(count))) }
        return parts.joined(separator: " · ")
    }

    /// Lecture files not in the list yet.
    var addable: [FolioDomain.Material] {
        (file?.lectureFiles ?? []).filter { m in !rows.contains { $0.id == m.id } }
    }

    func add(_ id: UUID) {
        edited = true
        rows.append(Row(id: id, first: session.flatMap { file?.resumePage(of: id, for: $0) } ?? 1))
        guard let m = file?.materials.first(where: { $0.id == id }) else { return }
        Task {
            if let n = await workspace.pageCount(of: m, course: courseId) { pageCounts[id] = n }
        }
    }

    func toggle(_ id: UUID) { change(id) { $0.included.toggle() } }
    func setFirst(_ id: UUID, _ page: Int?) { change(id) { $0.first = page } }
    func setLast(_ id: UUID, _ page: Int?) { change(id) { $0.last = page } }

    private func change(_ id: UUID, _ edit: (inout Row) -> Void) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        edited = true
        edit(&rows[i])
    }

    var action: SessionProgress {
        SessionProgress(course: courseId, session: sessionId,
                        ranges: rows.filter(\.included).map { SessionMaterial(materialId: $0.id, firstPage: $0.first, lastPage: $0.last) })
    }

    /// Why saving is off: a kept file without both pages says nothing about how far the class went.
    var refusal: String? {
        let kept = rows.filter(\.included)
        if kept.isEmpty { return String(localized: .sessionsProgressNothing) }
        if let row = kept.first(where: { $0.first == nil || $0.last == nil }) { return String(localized: .sessionsProgressMissingPages(name(row.id))) }
        return workspace.refusal(action)
    }

    var note: String? {
        refusal ?? (viewed.isEmpty ? nil : String(localized: .sessionsProgressFromRecording))
    }

    func record() { workspace.run(action) }
}
