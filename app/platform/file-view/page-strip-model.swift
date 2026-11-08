import FolioActions
import FolioDomain
import Foundation
import Observation

/// The page strip beside a lecture PDF (#147): the file's pages cut into sections, one per class that went through
/// them, each foldable under a one-line header; and a range picked on the thumbnails, saved as one class's progress
/// or as a class's pages changed. Saving is `material link`, the same action as the link popover and the wrap-up.
@MainActor @Observable
final class PageStripModel {
    struct Section: Identifiable, Equatable {
        /// The class's id.
        let id: UUID
        let pages: ClosedRange<Int>
        /// `10/28(수)`.
        let day: String
        var label: String { Session.pagesLabel(pages) }
    }

    struct Choice: Identifiable, Equatable {
        let id: UUID
        /// `10/14(수) 그래프 연결성`.
        let title: String
        /// `10/14(수)`.
        let day: String
        let today: Bool
    }

    /// One page with what heads it, or a folded section's header alone. A header is part of its first page's item
    /// rather than an item of its own: scrolled to, the two come into view together (as in `LectureSplitPane`).
    struct Item: Identifiable, Equatable {
        enum Lead: Equatable {
            case header(Section, open: Bool)
            /// The section being changed: its header turned into the row that saves it.
            case edit(Section)
            /// The row a new range is saved from, above its pages.
            case draft(ClosedRange<Int>)
        }

        let lead: Lead?
        let page: Int?
        let mark: Mark

        var id: ItemID {
            if let page { return .page(page) }
            if case .header(let s, _)? = lead { return .folded(s.id) }
            return .folded(UUID())
        }
    }

    enum ItemID: Hashable { case page(Int), folded(UUID) }

    enum Mark: Equatable {
        case plain
        /// In an unfolded section: the course-colour line runs down beside it, ending at the section's last page.
        case line(last: Bool)
        /// In the range being picked or changed.
        case picked
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
    /// The class menu of a new range is open.
    var choosing = false
    var chosen: UUID?
    /// The section just saved, lit for a moment so the eye finds where the row went.
    var fresh: UUID?
    /// Folded or unfolded by hand, per class; the rest follow `openByDefault`.
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
    var picks: Bool {
        guard let file, let materialId else { return false }
        return file.lectureFiles.contains { $0.id == materialId }
    }

    var sections: [Section] {
        guard picks, let file, let materialId else { return [] }
        return file.progressSections(of: materialId, pageCount: pageCount).compactMap { s in
            file.sessions.first { $0.id == s.session }.map { Section(id: s.session, pages: s.pages, day: file.day(of: $0, calendar: workspace.calendar)) }
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
        guard let materialId else { return }
        defaults?.set(Dictionary(uniqueKeysWithValues: folds.map { ($0.key.uuidString, $0.value) }), forKey: Self.key(materialId))
    }

    /// The column top to bottom: plain pages, each section's header with its pages when unfolded, and the row a range
    /// is saved from just above the pages it holds.
    var items: [Item] {
        var shown = sections
        if let editing, let selection, let i = shown.firstIndex(where: { $0.id == editing }) {
            shown[i] = Section(id: editing, pages: selection, day: shown[i].day)
        }
        func run(_ pages: ClosedRange<Int>, lead: Item.Lead, mark: (Int) -> Mark) -> [Item] {
            pages.map { Item(lead: $0 == pages.lowerBound ? lead : nil, page: $0, mark: mark($0)) }
        }
        var items: [Item] = []
        var page = 1
        while page <= pageCount {
            if let s = shown.first(where: { $0.pages.lowerBound == page }) {
                if s.id == editing {
                    items += run(s.pages, lead: .edit(s)) { _ in .picked }
                } else if isOpen(s) {
                    items += run(s.pages, lead: .header(s, open: true)) { .line(last: $0 == s.pages.upperBound) }
                } else {
                    items.append(Item(lead: .header(s, open: false), page: nil, mark: .plain))
                }
                page = s.pages.upperBound + 1
            } else if editing == nil, let selection, selection.lowerBound == page {
                items += run(selection, lead: .draft(selection)) { _ in .picked }
                page = selection.upperBound + 1
            } else {
                items.append(Item(lead: nil, page: page, mark: .plain))
                page += 1
            }
        }
        return items
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
        guard picks else { return }
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
        guard picks else { return }
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
    }

    private func clamp(_ pages: ClosedRange<Int>, to room: ClosedRange<Int>) -> ClosedRange<Int> {
        max(pages.lowerBound, room.lowerBound)...min(pages.upperBound, room.upperBound)
    }

    var selectionLabel: String? { selection.map(Session.pagesLabel) }

    // MARK: Saving

    /// Classes held so far that have no pages of this file yet, the latest first: a class with pages here is changed
    /// from its header instead. A cancelled class taught nothing.
    var choices: [Choice] {
        guard let file, let materialId else { return [] }
        let settings = workspace.settings, calendar = workspace.calendar
        let today = settings.studyDay(of: workspace.now, calendar: calendar)
        let held = Session.held(among: file.sessions.filter { !$0.isCancelled }, now: workspace.now, settings: settings, calendar: calendar)
        return held.reversed()
            .filter { s in s.materials.first { $0.materialId == materialId }?.pages == nil }
            .map { s in
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
}
