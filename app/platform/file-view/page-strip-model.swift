import FolioActions
import FolioDomain
import Foundation
import Observation

/// The page strip beside a lecture PDF (#147): the file's pages cut into sections, one per class that went through
/// them, each foldable under a one-line header; and a range picked on the thumbnails, saved as one class's progress
/// or as a class's pages changed. Saving is `material link`, the same action as the link popover and the wrap-up.
@MainActor @Observable
final class PageStripModel {
    /// A class's section: its id is the class's, its title the day (`10/28(수)`).
    typealias Section = StripSection
    typealias Item = StripItem
    typealias ItemID = StripItem.ID

    struct Choice: Identifiable, Equatable {
        let id: UUID
        /// `10/14(수) 그래프 연결성`.
        let title: String
        /// `10/14(수)`.
        let day: String
        let today: Bool
    }

    let workspace: Workspace
    let courseId: UUID?
    let materialId: UUID?
    let pageCount: Int

    /// The page a range starts from: the last one pressed without ⇧.
    private(set) var anchor: Int?
    /// The pages picked: a new range, or the changed range of `editing`.
    private(set) var selection: ClosedRange<Int>?
    /// The class whose pages are being changed, from its section's header.
    private(set) var editing: UUID?
    /// Picking turned on from the strip's button, a touch screen's way in that it can see: the next tap starts a range
    /// as a long press does.
    private(set) var picking = false
    /// The class menu of a new range is open.
    var choosing = false
    var chosen: UUID?
    /// The section just saved, lit for a moment so the eye finds where the row went.
    var fresh: UUID?
    /// Folded or unfolded by hand, per class; the rest follow `isOpen`'s default.
    private var folds: [UUID: Bool]
    @ObservationIgnored private let defaults: UserDefaults?

    init(workspace: Workspace, course: UUID?, material: UUID?, pageCount: Int, defaults: UserDefaults? = PageStripModel.sharedDefaults) {
        self.workspace = workspace
        courseId = course
        materialId = material
        self.pageCount = pageCount
        self.defaults = defaults
        let saved = material.flatMap { defaults?.dictionary(forKey: Self.key($0)) as? [String: Bool] } ?? [:]
        folds = Dictionary(uniqueKeysWithValues: saved.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }

    /// A test host or a window-snapshot run shares the installed app's bundle ID, so its defaults are the user's: what
    /// it folds would show up folded there.
    static var sharedDefaults: UserDefaults? {
        #if DEBUG && os(macOS)
        if SnapshotDriver.directory != nil { return nil }
        #endif
        return LocalFolders.isIsolated() ? nil : .standard
    }

    static func key(_ material: UUID) -> String { "pageStripFolds.\(material.uuidString)" }

    private var file: CourseFile? { courseId.flatMap { workspace.course($0)?.file } }

    /// Only a course's lecture files have progress: the same files the wrap-up asks about.
    var isLecture: Bool {
        guard let file, let materialId else { return false }
        return file.lectureFiles.contains { $0.id == materialId }
    }

    var sections: [Section] {
        guard isLecture, let file, let materialId else { return [] }
        return file.progressSections(of: materialId, pageCount: pageCount).compactMap { s in
            file.sessions.first { $0.id == s.session }.map { Section(id: s.session, pages: s.pages, title: file.day(of: $0, calendar: workspace.calendar)) }
        }
    }

    // MARK: Folding

    /// Unfolded until folded by hand: the two latest sections, where the lecture is now and the class before it.
    /// Earlier ones fold, so a long file opens on its recent pages rather than a wall of finished ones.
    func isOpen(_ section: Section) -> Bool {
        if let set = folds[section.id] { return set }
        let all = sections
        guard let i = all.firstIndex(where: { $0.id == section.id }) else { return true }
        return i >= all.count - 2
    }

    func toggle(_ section: Section) { setOpen(section.id, !isOpen(section)) }

    private func setOpen(_ session: UUID, _ open: Bool) {
        folds[session] = open
        saveFolds()
    }

    private func saveFolds() {
        guard let materialId else { return }
        defaults?.set(Dictionary(uniqueKeysWithValues: folds.map { ($0.key.uuidString, $0.value) }), forKey: Self.key(materialId))
    }

    /// The column top to bottom: plain pages, each section's header with its pages when unfolded, and the row a range
    /// is saved from just above the pages it holds.
    var items: [Item] {
        var shown = sections
        if let editing, let selection, let i = shown.firstIndex(where: { $0.id == editing }) {
            shown[i] = Section(id: editing, pages: selection, title: shown[i].title)
        }
        return Item.column(pageCount: pageCount, sections: shown, editing: editing, draft: editing == nil ? selection : nil,
                           draftBelow: draftBelow, isOpen: isOpen)
    }

    /// A new range's row stands at the end it was picked out to, so it is saved where ⇧ (or the next tap) ended it:
    /// under the range when picked downward from the anchor. Picked upward, or one page alone, it stays over it. A
    /// class's range being changed keeps its row in the header's place.
    var draftBelow: Bool {
        guard editing == nil, let selection, let anchor else { return false }
        return selection.lowerBound == anchor && selection.upperBound > anchor
    }

    /// The page whose item holds a new range's row, for the column to keep it in sight as it moves end to end.
    var draftItemID: ItemID? {
        guard editing == nil, let selection else { return nil }
        return .page(draftBelow ? selection.upperBound : selection.lowerBound)
    }

    /// Where the column scrolls for the PDF's page: the page, or the header of the folded section holding it.
    func itemID(showing page: Int) -> ItemID {
        if let s = sections.first(where: { $0.pages.contains(page) && $0.id != editing && !isOpen($0) }) { return .folded(s.id) }
        return .page(page)
    }

    // MARK: Picking

    /// Pages the other classes took: where a range picked here stops.
    private var taken: [ClosedRange<Int>] {
        sections.filter { $0.id != editing }.map(\.pages)
    }

    /// A press without ⇧: the page a range will start from, and any range picked or being changed is let go.
    func press(_ page: Int) {
        clear()
        anchor = page
    }

    /// ⇧-press, or on a touch screen a tap while a range is up. A new range runs from the anchor to `page` either way
    /// round; a class's range being changed moves its end to `page`, or its start when `page` is before it. Either
    /// stops at another class's pages, which a range never shares (`Session.progressOverlap`).
    func extend(to page: Int) {
        guard isLecture else { return }
        if picking, selection == nil { return start(at: page) }
        if editing != nil, let selection {
            guard let room = PageRange.room(at: selection.lowerBound, besides: taken, pages: pageCount) else { return }
            let wanted = page >= selection.lowerBound ? selection.lowerBound...page : page...selection.upperBound
            self.selection = clamp(wanted, to: room)
            return
        }
        let from = anchor ?? page
        guard let room = PageRange.room(at: from, besides: taken, pages: pageCount) else { return }
        anchor = from
        selection = clamp(min(from, page)...max(from, page), to: room)
        pickDefaultClass()
    }

    /// A long press, the touch screen's way in: a range of that one page, which the next taps widen. On a section's
    /// page it changes that class's range instead, as its header would.
    func start(at page: Int) {
        guard isLecture else { return }
        if let section = sections.first(where: { $0.pages.contains(page) }) { return edit(section) }
        guard PageRange.room(at: page, besides: taken, pages: pageCount) != nil else { return }
        clear()
        anchor = page
        selection = page...page
        pickDefaultClass()
    }

    /// The header pressed: its range becomes the one being changed.
    func edit(_ section: Section) {
        clear()
        editing = section.id
        selection = section.pages
        anchor = section.pages.lowerBound
    }

    func clear() {
        selection = nil
        editing = nil
        choosing = false
        picking = false
    }

    /// The strip's button: on, the next tap starts a range; on again while a range is up, it is let go.
    func togglePicking() {
        if picking || selection != nil { return clear() }
        anchor = nil
        picking = true
    }

    /// Picking from the button, or a range up from a long press or a header: what the button shows as on.
    var pickingShown: Bool { picking || selection != nil }

    private func clamp(_ pages: ClosedRange<Int>, to room: ClosedRange<Int>) -> ClosedRange<Int> {
        max(pages.lowerBound, room.lowerBound)...min(pages.upperBound, room.upperBound)
    }

    var selectionLabel: String? { selection.map(Session.pagesLabel) }

    // MARK: Saving

    var choices: [Choice] {
        guard let file, let materialId else { return [] }
        let settings = workspace.settings, calendar = workspace.calendar
        let today = settings.studyDay(of: workspace.now, calendar: calendar)
        return file.sessionsForNewRange(of: materialId, now: workspace.now, settings: settings, calendar: calendar).map { s in
            Choice(id: s.id, title: file.title(of: s, calendar: calendar), day: file.day(of: s, calendar: calendar),
                   today: settings.studyDay(of: s.date, calendar: calendar) == today)
        }
    }

    /// Today's class is the one to save as, alone: no menu to open.
    var onlyToday: Choice? {
        let all = choices
        return all.count == 1 && all[0].today ? all[0] : nil
    }

    private func pickDefaultClass() {
        let all = choices
        if let chosen, all.contains(where: { $0.id == chosen }) { return }
        chosen = (all.first { $0.today } ?? all.first)?.id
    }

    var chosenChoice: Choice? { choices.first { $0.id == chosen } }

    var action: MaterialLinkSession? {
        guard let courseId, let materialId, let selection, let session = editing ?? chosen else { return nil }
        return MaterialLinkSession(course: courseId, material: materialId, session: session,
                                   firstPage: selection.lowerBound, lastPage: selection.upperBound)
    }

    var refusal: String? { action.flatMap { workspace.refusal($0) } }
    var canSave: Bool {
        guard let action else { return false }
        if let editing, sections.first(where: { $0.id == editing })?.pages == selection { return false }
        return workspace.can(action)
    }

    func commit() {
        guard let action, let session = editing ?? chosen, workspace.run(action) != nil else { return }
        if editing == nil {
            setOpen(session, true)
            fresh = session
        }
        clear()
    }

    // MARK: Removing

    /// Takes the file off the class, as unticking its row in the wrap-up does. Not confirmed: no file goes, only the
    /// link, and the range can be picked again.
    private func removal(of session: UUID) -> MaterialLinkSession? {
        guard let courseId, let materialId else { return nil }
        return MaterialLinkSession(course: courseId, material: materialId, session: session, linked: false)
    }

    var canRemove: Bool { editing.map { canRemove($0) } ?? false }

    func canRemove(_ section: Section) -> Bool { canRemove(section.id) }

    private func canRemove(_ session: UUID) -> Bool { removal(of: session).map { workspace.can($0) } ?? false }

    /// The section being changed, from its row.
    func remove() {
        guard let editing else { return }
        unlink(editing)
    }

    /// A header's menu: straight from the section, without changing its range first.
    func remove(_ section: Section) { unlink(section.id) }

    private func unlink(_ session: UUID) {
        guard let action = removal(of: session), workspace.run(action) != nil else { return }
        forgetFold(session)
        if fresh == session { fresh = nil }
        // Only the section's own row closes: from another header's menu, a range being changed or picked stays. A new
        // range can't hold the removed section's pages, so nothing picked goes stale.
        if editing == session { clear() }
    }

    /// A fold kept for a class with no section here would come back on its next range, folded or not as it was.
    private func forgetFold(_ session: UUID) {
        guard folds.removeValue(forKey: session) != nil else { return }
        saveFolds()
    }
}
