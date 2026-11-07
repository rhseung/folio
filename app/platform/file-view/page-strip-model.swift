import FolioActions
import FolioDomain
import Foundation
import Observation

/// The page strip beside a PDF: which classes went through which pages (a bracket each, beside the thumbnails), and a
/// range picked on the thumbnails to save as one class's progress (#147). The range is saved by `material link`, the
/// same action as the link popover's page bar and the class wrap-up.
@MainActor @Observable
final class PageStripModel {
    struct Bracket: Identifiable, Equatable {
        var id: UUID { session }
        let session: UUID
        let pages: ClosedRange<Int>
        /// 0 beside the thumbnails, further out for a range overlapping one nearer.
        let lane: Int
        /// `11/3(화)`.
        let day: String
        var link: AppLink { AppLink(.session, session) }
    }

    struct Choice: Identifiable, Equatable {
        let id: UUID
        /// `11/3(화): 매칭`.
        let title: String
        /// What the class already says it went through in this file.
        let range: ClosedRange<Int>?
        var pages: String? { range.map(PageStripModel.label) }
    }

    let workspace: Workspace
    let courseId: UUID?
    let materialId: UUID?
    let pageCount: Int

    /// The page a range starts from: the last one pressed without ⇧.
    private(set) var anchor: Int?
    /// The pages picked, shown as the band; nil when none are.
    private(set) var selection: ClosedRange<Int>?
    /// The class popover is open.
    var choosing = false
    var chosen: UUID?

    init(workspace: Workspace, course: UUID?, material: UUID?, pageCount: Int) {
        self.workspace = workspace
        courseId = course
        materialId = material
        self.pageCount = pageCount
    }

    private var file: CourseFile? { courseId.flatMap { workspace.course($0)?.file } }

    /// Only a course's lecture files have progress: the same files the wrap-up asks about.
    var picks: Bool {
        guard let file, let materialId else { return false }
        return file.lectureFiles.contains { $0.id == materialId }
    }

    var brackets: [Bracket] {
        guard picks, let file, let materialId else { return [] }
        return file.progressBrackets(of: materialId, pageCount: pageCount).compactMap { b in
            file.sessions.first { $0.id == b.session }.map {
                Bracket(session: b.session, pages: b.pages, lane: b.lane, day: file.day(of: $0, calendar: workspace.calendar))
            }
        }
    }

    var lanes: Int { (brackets.map(\.lane).max() ?? -1) + 1 }

    // MARK: Picking

    /// A press without ⇧: the page a range will start from, and any range picked before is let go.
    func press(_ page: Int) {
        anchor = page
        selection = nil
        choosing = false
    }

    /// ⇧-press, or on a touch screen a tap while a range is up: from the anchor to `page`, either way round.
    func extend(to page: Int) {
        guard picks else { return }
        let from = anchor ?? page
        anchor = from
        selection = min(from, page)...max(from, page)
    }

    /// A long press, the touch screen's way in: a range of that one page, which the next taps widen.
    func start(at page: Int) {
        guard picks else { return }
        anchor = page
        selection = page...page
    }

    func clear() {
        selection = nil
        choosing = false
    }

    var selectionLabel: String? {
        selection.map(Self.label)
    }

    nonisolated static func label(_ pages: ClosedRange<Int>) -> String {
        pages.count == 1 ? String(localized: .fileViewProgressPage(pages.lowerBound))
            : String(localized: .fileViewProgressPages(pages.lowerBound, pages.upperBound))
    }

    // MARK: Saving

    /// The classes held up to today, the latest first: the one just over is the likeliest. A cancelled class taught
    /// nothing and isn't offered.
    var choices: [Choice] {
        guard let file, let materialId else { return [] }
        let held = Session.held(among: file.sessions.filter { !$0.isCancelled }, now: workspace.now, settings: workspace.settings,
                                calendar: workspace.calendar)
        return held.reversed().map { s in
            Choice(id: s.id, title: file.title(of: s, calendar: workspace.calendar),
                   range: s.materials.first { $0.materialId == materialId }?.pages)
        }
    }

    /// Opens the popover on today's class, or the last one before it.
    func choose() {
        guard selection != nil else { return }
        if chosen == nil || !choices.contains(where: { $0.id == chosen }) { chosen = choices.first?.id }
        choosing = true
    }

    var action: MaterialLinkSession? {
        guard let courseId, let materialId, let chosen, let selection else { return nil }
        return MaterialLinkSession(course: courseId, material: materialId, session: chosen,
                                   firstPage: selection.lowerBound, lastPage: selection.upperBound)
    }

    var refusal: String? { action.flatMap { workspace.refusal($0) } }
    var canSave: Bool { action.map { workspace.can($0) } ?? false }

    /// The class's own pages of this file that saving replaces, said before they go.
    var replaces: String? {
        guard let chosen, let choice = choices.first(where: { $0.id == chosen }), let range = choice.range, range != selection,
              let pages = choice.pages else { return nil }
        return String(localized: .fileViewProgressReplaces(pages))
    }

    func commit() {
        guard let action, workspace.run(action) != nil else { return }
        clear()
    }
}
