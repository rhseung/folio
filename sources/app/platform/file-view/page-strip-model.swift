import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class PageStripModel {
    typealias Section = StripSection
    typealias Item = StripItem
    typealias ItemID = StripItem.ID

    struct Choice: Identifiable, Equatable {
        let id: UUID
        let title: String
        let day: String
        let today: Bool
    }

    let workspace: Workspace
    let courseId: UUID?
    let materialId: UUID?
    let pageCount: Int

    private(set) var anchor: Int?
    private(set) var selection: ClosedRange<Int>?
    private(set) var editing: UUID?
    private(set) var picking = false
    var choosing = false
    var chosen: UUID?
    var fresh: UUID?
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

    // 테스트 호스트와 창 스냅숏 실행은 설치한 앱과 bundle ID가 같아서 UserDefaults도 사용자의 것을 쓴다. 여기서 접은 구획이 사용자의 앱에서도 접혀 보이게 된다.
    static var sharedDefaults: UserDefaults? {
        #if DEBUG && os(macOS)
        if SnapshotDriver.directory != nil { return nil }
        #endif
        return LocalFolders.isIsolated() ? nil : .standard
    }

    static func key(_ material: UUID) -> String { "pageStripFolds.\(material.uuidString)" }

    private var file: CourseFile? { courseId.flatMap { workspace.course($0)?.file } }

    var isLecture: Bool {
        guard let file, let materialId else { return false }
        return file.lectureFiles.contains { $0.id == materialId }
    }

    var sections: [Section] {
        guard isLecture, let file, let materialId else { return [] }
        return file.progressSections(of: materialId, pageCount: pageCount).compactMap { s in
            file.sessions.first { $0.id == s.session }.map {
                Section(id: s.session, pages: s.pages, title: file.day(of: $0, calendar: workspace.calendar))
            }
        }
    }

    // MARK: Folding

    func isOpen(_ section: Section) -> Bool { isOpen(section, among: sections) }

    // `sections`는 읽을 때마다 과목의 회차를 다시 읽으므로, 열을 한 번 훑을 때는 이미 읽은 구획을 넘겨받는다.
    private func isOpen(_ section: Section, among all: [Section]) -> Bool {
        if let set = folds[section.id] { return set }
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

    var items: [Item] {
        let all = sections
        var shown = all
        if let editing, let selection, let i = shown.firstIndex(where: { $0.id == editing }) {
            shown[i] = Section(id: editing, pages: selection, title: shown[i].title)
        }
        return Item.column(
            pageCount: pageCount, sections: shown, editing: editing, draft: editing == nil ? selection : nil,
            draftBelow: draftBelow, isOpen: { self.isOpen($0, among: all) })
    }

    var draftBelow: Bool {
        guard editing == nil, let selection, let anchor else { return false }
        return selection.lowerBound == anchor && selection.upperBound > anchor
    }

    var draftItemID: ItemID? {
        guard editing == nil, let selection else { return nil }
        return .page(draftBelow ? selection.upperBound : selection.lowerBound)
    }

    func itemID(showing page: Int) -> ItemID {
        let all = sections
        if let s = all.first(where: { $0.pages.contains(page) && $0.id != editing && !isOpen($0, among: all) }) { return .folded(s.id) }
        return .page(page)
    }

    // MARK: Picking

    private var taken: [ClosedRange<Int>] {
        sections.filter { $0.id != editing }.map(\.pages)
    }

    func press(_ page: Int) {
        clear()
        anchor = page
    }

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

    func start(at page: Int) {
        guard isLecture else { return }
        if let section = sections.first(where: { $0.pages.contains(page) }) { return edit(section) }
        guard PageRange.room(at: page, besides: taken, pages: pageCount) != nil else { return }
        clear()
        anchor = page
        selection = page...page
        pickDefaultClass()
    }

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

    func togglePicking() {
        if picking || selection != nil { return clear() }
        anchor = nil
        picking = true
    }

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
            Choice(
                id: s.id, title: file.title(of: s, calendar: calendar), day: file.day(of: s, calendar: calendar),
                today: settings.studyDay(of: s.date, calendar: calendar) == today)
        }
    }

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
        return MaterialLinkSession(
            course: courseId, material: materialId, session: session,
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

    private func removal(of session: UUID) -> MaterialLinkSession? {
        guard let courseId, let materialId else { return nil }
        return MaterialLinkSession(course: courseId, material: materialId, session: session, linked: false)
    }

    var canRemove: Bool { editing.map { canRemove($0) } ?? false }

    func canRemove(_ section: Section) -> Bool { canRemove(section.id) }

    private func canRemove(_ session: UUID) -> Bool { removal(of: session).map { workspace.can($0) } ?? false }

    func remove() {
        guard let editing else { return }
        unlink(editing)
    }

    func remove(_ section: Section) { unlink(section.id) }

    private func unlink(_ session: UUID) {
        guard let action = removal(of: session), workspace.run(action) != nil else { return }
        forgetFold(session)
        if fresh == session { fresh = nil }
        if editing == session { clear() }
    }

    private func forgetFold(_ session: UUID) {
        guard folds.removeValue(forKey: session) != nil else { return }
        saveFolds()
    }
}
