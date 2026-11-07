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

        var range: PageRange {
            get { PageRange(first: first, last: last) }
            set {
                first = newValue.first
                last = newValue.last
            }
        }
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
        // A recording just stopped isn't in course.json yet, so the ask passes its pages; opened later, the session's
        // recordings have them.
        let file = workspace.course(course)?.file
        self.viewed = viewed.isEmpty ? file.flatMap { f in f.sessions.first { $0.id == session }.map(f.viewedPages(of:)) } ?? [] : viewed
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

    var accent: CourseAccent { workspace.accent(courseId) }

    func taught(_ id: UUID) -> [PageRangeField.Taught] {
        guard let file else { return [] }
        return PageRangeField.Taught.list(file, material: id, besides: sessionId, calendar: workspace.calendar)
    }

    func seen(_ id: UUID) -> ClosedRange<Int>? { viewed.first { $0.materialId == id }?.pages }

    func resume(_ id: UUID) -> Int? {
        guard let file, let session else { return nil }
        return file.resumePage(of: id, for: session)
    }

    /// Lecture files not in the list yet.
    var addable: [FolioDomain.Material] {
        (file?.lectureFiles ?? []).filter { m in !rows.contains { $0.id == m.id } }
    }

    func add(_ id: UUID) {
        edited = true
        guard let file, let session else { return }
        let range = file.suggestedRange(of: id, for: session, seen: viewed.first { $0.materialId == id }, pageCount: nil)
        rows.append(Row(id: id, first: range.firstPage, last: range.lastPage))
        guard let m = file.materials.first(where: { $0.id == id }) else { return }
        Task {
            if let n = await workspace.pageCount(of: m, course: courseId) {
                pageCounts[id] = n
                // The suggestion was made without the count; it stays within the file now that it's known.
                change(id) { row in row.range = row.range.moving(.first, to: row.first, pages: n) }
            }
        }
    }

    func toggle(_ id: UUID) { change(id) { $0.included.toggle() } }
    func setRange(_ id: UUID, _ range: PageRange) { change(id) { $0.range = range } }

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
