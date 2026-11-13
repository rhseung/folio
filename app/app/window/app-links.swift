import FolioDomain
import FolioMarkdown
import FolioStorage
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Kept apart from the link, so any link opens in any of them.
enum LinkPlacement: CaseIterable {
    case here
    case beside
    case tab
    case window

    var title: String {
        switch self {
        case .here: String(localized: .linkOpenHere)
        case .beside: String(localized: .linkOpenBeside)
        case .tab: String(localized: .linkOpenTab)
        case .window: String(localized: .linkOpenWindow)
        }
    }

    var symbol: String {
        switch self {
        case .here: "arrow.right.circle"
        case .beside: "rectangle.split.2x1"
        case .tab: "plus.rectangle.on.rectangle"
        case .window: "macwindow.badge.plus"
        }
    }
}

/// Screens call this instead of choosing a destination themselves, so every
/// way of moving lands in the window's one history. `course` names where the target likely is; it is only a hint.
struct OpenLinkAction {
    var handler: @MainActor (AppLink, LinkPlacement, UUID?) -> Void = { _, _, _ in }

    @MainActor func callAsFunction(_ link: AppLink, in placement: LinkPlacement = .here, course: UUID? = nil) {
        handler(link, placement, course)
    }
}

extension EnvironmentValues {
    @Entry var openLink = OpenLinkAction()
    /// What the window shows, for the screen drawing it to follow.
    @Entry var place: Navigator.Entry?
}

@MainActor @Observable
final class Navigator {
    /// The course is worked out once when the link is opened rather than on every redraw.
    struct Entry: Equatable, Sendable, Codable {
        var link: AppLink
        var course: UUID?
    }

    private(set) var history: LinkHistory<Entry>

    init(_ start: Entry = Entry(link: .place(.today))) {
        history = LinkHistory(start)
    }

    /// A tab moved to a window of its own goes on from where it was, back and forward included.
    init(history: LinkHistory<Entry>) {
        self.history = history
    }

    var current: Entry { history.current }

    var screen: Screen { Screen(current) }

    /// The same target with another page or heading takes the step it is on rather than a new one: a PDF opened at
    /// one page and then another is still one visit.
    func go(_ entry: Entry) {
        if entry.link.withoutAnchor == current.link.withoutAnchor, entry.course == current.course {
            history.replace(entry)
        } else {
            history.visit(entry)
        }
    }

    func back(_ steps: Int = 1) { history.goBack(steps) }
    func forward(_ steps: Int = 1) { history.goForward(steps) }

    /// Nearest first, for the list a held button shows.
    var backList: [Entry] { history.back.reversed() }
    var forwardList: [Entry] { history.forward }

    /// Where a `folio://` link from outside the app (a calendar note, Obsidian, `folio open`) opens, `age` after this
    /// window was made: in a new tab of the window in front, so the page it shows stays as it was. A window made a moment ago that
    /// hasn't moved is the one the system made to receive the link, there being none open, and shows it itself; a tab
    /// would leave an empty Today behind it.
    func outsidePlacement(windowAge age: TimeInterval) -> LinkPlacement {
        let untouched = !history.canGoBack && !history.canGoForward && current == Entry(link: .place(.today))
        return untouched && age < Self.freshWindow ? .here : .tab
    }

    /// The system shows a window it makes for a link and hands it the link within a moment; nobody follows a link
    /// from another app that soon after opening a window themselves.
    static let freshWindow: TimeInterval = 2
}

extension Workspace {
    /// Where a link points, or nil when nothing it names is here (a deleted exam, a link from another GIST folder).
    /// Looked for where its kind lives (`AppLink.Kind.home`), so a new kind is found as soon as it says where that is.
    func entry(for link: AppLink, hint: UUID? = nil) -> Navigator.Entry? {
        switch link.kind.home {
        case .app:
            // Settings' tab is filled in here, so every step in a history names its tab and going back to one shows that tab.
            return Navigator.Entry(link: link.kind == .settings ? .settings(link.settingsPage ?? SettingsTab.remembered.page) : link)
        case .transcript:
            return transcript.semesters.contains { $0.id == link.id } ? Navigator.Entry(link: link) : nil
        case .catalog:
            return catalog.people.contains { $0.id == link.id } ? Navigator.Entry(link: link) : nil
        case .quiz:
            return course(holdingCard: link.id, hint: hint).map { Navigator.Entry(link: link, course: $0) }
        case .course:
            // The hint first: the course a screen links from usually holds what it links to.
            let files = (hint.flatMap(course).map { [$0] } ?? []) + courses
            return link.course(in: files.map(\.file)).map { Navigator.Entry(link: link, course: $0) }
        }
    }

    /// Cards live in each unit's quiz file, read only here, on a click.
    private func course(holdingCard id: UUID?, hint: UUID?) -> UUID? {
        guard let id else { return nil }
        let ordered = (hint.flatMap(course).map { [$0] } ?? []) + courses.filter { $0.id != hint }
        for c in ordered {
            for unit in c.file.units where (try? c.store.loadQuiz(unit: unit.id).model.cards.contains { $0.id == id }) == true {
                return c.id
            }
        }
        return nil
    }

    func title(of entry: Navigator.Entry) -> String {
        let link = entry.link
        let item = itemName(of: entry)
        if let loaded = entry.course.flatMap(course) {
            return [loaded.title, item].compactMap { $0 }.joined(separator: " · ")
        }
        switch link.kind {
        case .today: return String(localized: .rootNavToday)
        case .grades: return String(localized: .rootNavGrades)
        case .requirements: return String(localized: .rootNavRequirements)
        case .people: return String(localized: .rootNavPeople)
        case .codes: return String(localized: .rootNavCodes)
        case .whatsNew: return String(localized: .whatsNewTitle)
        case .proposals: return String(localized: .rootNavProposals)
        case .settings:
            return [String(localized: .rootNavSettings), link.settingsPage.map { SettingsTab($0).label }].compactMap { $0 }.joined(separator: " · ")
        case .semester: return transcript.semesters.first { $0.id == link.id }?.title ?? ""
        case .person: return item ?? String(localized: .rootNavPeople)
        // A course's item whose course is gone: the address, as its screen says it can't be found.
        case .course, .session, .unit, .note, .material, .assignment, .exam, .problemSet, .card, .recording: return link.string
        }
    }

    /// What a step shows inside its screen: a course's section, or the session, note, file, exam or card it opened, or
    /// a person. Nil for the screen itself.
    func itemName(of entry: Navigator.Entry) -> String? {
        let link = entry.link
        let file = entry.course.flatMap(course)?.file
        let name = { (path: String) in ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
        switch link.kind {
        case .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals, .semester: return nil
        case .person: return catalog.people.first { $0.id == link.id }?.name
        case .course: return file.flatMap { _ in link.page.map { CourseSection($0).title } }
        case .session: return file.flatMap { f in f.sessions.first { $0.id == link.id }.map { f.title(of: $0, calendar: calendar) } }
        case .unit: return file?.units.first { $0.id == link.id }?.title
        case .note: return file?.notes.first { $0.id == link.id }.map { name($0.path) }
        case .material: return file?.materials.first { $0.id == link.id }.map { ($0.path as NSString).lastPathComponent }
        case .assignment: return file?.assignments.first { $0.id == link.id }?.title
        case .exam: return file?.exams.first { $0.id == link.id }?.title
        case .problemSet: return file?.problemSets.first { $0.id == link.id }?.title
        case .recording: return file.flatMap { f in f.recordings.first { $0.id == link.id }.map { RecordingPlayerModel.name(of: $0, in: f, calendar: calendar) } }
        // A card's prompt is a sentence in a quiz file read only on a click; the page it is on names it well enough.
        case .card: return file.map { _ in CourseSection.quizCards.title }
        }
    }

    /// Nil when nothing here has it (deleted, or from another GIST folder).
    func name(of link: AppLink) -> String? {
        // A place is named as it is written, not with the settings tab opening it would fill in.
        guard let entry = link.kind.isPlace ? Navigator.Entry(link: link) : entry(for: link) else { return nil }
        return link.kind == .course ? title(of: entry) : itemName(of: entry) ?? title(of: entry)
    }

    func label(of link: AppLink) -> String? {
        name(of: link).map(link.label)
    }
}

extension AppLink {
    func label(_ name: String) -> String {
        let part: String? = switch anchor {
        case .page(let n): String(localized: .notesAssistLinkPage(n))
        case .heading(let heading): heading
        case .block(let block): "^" + block
        case .time(let t): AppLink.clock(t)
        case nil: nil
        }
        return [name, part].compactMap { $0 }.joined(separator: " › ")
    }

    /// What pasting this address into a note writes: the link as link completion writes it, by kind and ID with the
    /// item's name (`[[material:<ID>#page=2|05_Matchings.pdf]]`). A place or a course's page has no `<kind>:<ID>`
    /// form and goes between the brackets as its address, which the note reads the same way.
    func noteLink(named name: String?) -> String {
        let fragment: String?? = switch anchor {
        case .page(let n): "page=\(n)"
        case .block(let block): "^" + block
        case .heading(let heading): WikiLink.linkable(heading: heading) ? heading : .none
        case .time(let t): "t=" + AppLink.clock(t)
        case nil: .some(nil)
        }
        guard let id, page == nil, let fragment, WikiLink.objectKinds.contains(kind.rawValue) else {
            return WikiLink.written(address: string, alias: name)
        }
        return WikiLink.written(kind.rawValue, id, fragment: fragment, alias: name)
    }
}

extension AppLink.Anchor {
    var isBlock: Bool {
        if case .block = self { true } else { false }
    }

    /// For the editor's caret; nil when the note has none.
    func location(in text: String) -> Int? {
        switch self {
        case .heading(let heading): ParsedNote.location(in: text, heading: heading, block: nil)
        case .block(let block): ParsedNote.location(in: text, heading: nil, block: block)
        case .page, .time: nil
        }
    }
}

extension CourseSection {
    init(_ page: AppLink.CoursePage) {
        self = switch page {
        case .overview: .overview
        case .sessions: .sessions
        case .units: .units
        case .notes: .notes
        case .materials: .materials
        case .quiz: .quizSolve
        case .cards: .quizCards
        case .stats: .quizStats
        case .problems: .quizProblems
        case .assignments: .assignments
        case .exams: .exams
        case .grades: .grades
        }
    }

    var page: AppLink.CoursePage {
        switch self {
        case .overview: .overview
        case .sessions: .sessions
        case .units: .units
        case .notes: .notes
        case .materials: .materials
        case .quizSolve: .quiz
        case .quizCards: .cards
        case .quizStats: .stats
        case .quizProblems: .problems
        case .assignments: .assignments
        case .exams: .exams
        case .grades: .grades
        }
    }
}

/// Where a click on a link written in a note, a file or a Claude answer goes, from every view that shows one.
@MainActor enum NoteLinks {
    static func open(_ href: String, base: URL?, in placement: LinkPlacement = .here, openNote: (String) -> Void, openLink: OpenLinkAction) {
        // A web view hands its links over as URLs, with a block's `^` escaped, which only the URL reading takes back.
        if let link = URL(string: href).flatMap(AppLink.init(url:)) ?? AppLink(string: href) {
            openLink(link, in: placement)
            return
        }
        guard let url = URL(string: href, relativeTo: base) ?? URL(string: href.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "") else { return }
        // `[[노트 제목]]` written by hand names a note by its title; a link by ID (`[[note:<ID>]]`) is an app link above.
        if let title = AppLink.noteTitle(url) { return openNote(title) }
        switch url.scheme {
        case "file" where url.pathExtension == "md":
            openNote(url.deletingPathExtension().lastPathComponent)
        case "http", "https", "obsidian", "mailto":
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        default:
            break
        }
    }

    /// Whether `href` is something the app opens itself, which can then also open in a tab or a window.
    static func isAppLink(_ href: String) -> Bool { AppLink(string: href) != nil }
}

/// Puts a link on the clipboard: as a URL for apps that take one, and as text, which a note turns into a link.
@MainActor func copyLink(_ link: AppLink) {
    #if os(macOS)
    let board = NSPasteboard.general
    board.clearContents()
    board.writeObjects([link.url as NSURL])
    board.setString(link.string, forType: .string)
    #else
    UIPasteboard.general.items = [[UTType.url.identifier: link.url, UTType.plainText.identifier: link.string]]
    #endif
}

/// "여기서 열기 · 옆 칸에서 열기 · 새 탭에서 열기 · 새 창에서 열기 · 링크 복사", the same in every item's and link's menu.
/// A row whose menu leads with its own actions takes the openings and the link as one 공유 ▸ submenu, after a divider
/// (`trailing`), as item menus do (#403).
struct LinkMenu: View {
    let link: AppLink
    var course: UUID?
    var copies = true
    var trailing = false
    @Environment(\.openLink) private var openLink
    @Environment(\.supportsMultipleWindows) private var multipleWindows

    var body: some View {
        if trailing {
            Divider()
            ShareMenu(link: link, course: course)
        } else {
            openings
            if copies {
                Divider()
                Button(.linkCopy, systemImage: "link") { copyLink(link) }
            }
        }
    }

    var openings: some View {
        ForEach(LinkMenu.placements(multipleWindows: multipleWindows), id: \.self) { placement in
            Button(placement.title, systemImage: placement.symbol) { openLink(link, in: placement, course: course) }
        }
    }

    /// Without more windows (an iPad set to one), here and the pane beside are left.
    static func placements(multipleWindows: Bool) -> [LinkPlacement] {
        multipleWindows ? LinkPlacement.allCases : [.here, .beside]
    }
}

/// A PDF's link annotations: a `folio://` link (a `\href` in a built `.tex`, a link in a slide) opens in the app,
/// anything else as PDFKit would. Clicks that jump back to the source (SyncTeX) are not links and don't come here.
@MainActor final class PDFLinks: NSObject, PDFViewDelegate {
    private var opener: OpenLinkAction
    private static var key = 0

    private init(opener: OpenLinkAction) { self.opener = opener }

    /// The view holds its delegate weakly, so the delegate is kept on the view itself.
    static func attach(to view: PDFView, opener: OpenLinkAction) {
        if let links = objc_getAssociatedObject(view, &key) as? PDFLinks {
            links.opener = opener
            return
        }
        let links = PDFLinks(opener: opener)
        objc_setAssociatedObject(view, &key, links, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        view.delegate = links
    }

    nonisolated func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
        MainActor.assumeIsolated {
            if let link = AppLink(url: url) {
                opener(link)
            } else {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
            }
        }
    }
}
