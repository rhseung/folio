import FolioDomain
import FolioMarkdown
import FolioStorage
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

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

struct OpenLinkAction {
    var handler: @MainActor (AppLink, LinkPlacement, UUID?) -> Void = { _, _, _ in }

    @MainActor func callAsFunction(_ link: AppLink, in placement: LinkPlacement = .here, course: UUID? = nil) {
        handler(link, placement, course)
    }
}

extension EnvironmentValues {
    @Entry var openLink = OpenLinkAction()
    @Entry var place: Navigator.Entry?
}

@MainActor @Observable
final class Navigator {
    struct Entry: Equatable, Sendable, Codable {
        var link: AppLink
        var course: UUID?
    }

    private(set) var history: LinkHistory<Entry>

    init(_ start: Entry = Entry(link: .place(.today))) {
        history = LinkHistory(start)
    }

    init(history: LinkHistory<Entry>) {
        self.history = history
    }

    var current: Entry { history.current }

    var screen: Screen { Screen(current) }

    func go(_ entry: Entry) {
        if entry.link.withoutAnchor == current.link.withoutAnchor, entry.course == current.course {
            history.replace(entry)
        } else {
            history.visit(entry)
        }
    }

    func back(_ steps: Int = 1) { history.goBack(steps) }
    func forward(_ steps: Int = 1) { history.goForward(steps) }

    var backList: [Entry] { history.back.reversed() }
    var forwardList: [Entry] { history.forward }

    func outsidePlacement(windowAge age: TimeInterval) -> LinkPlacement {
        let untouched = !history.canGoBack && !history.canGoForward && current == Entry(link: .place(.today))
        return untouched && age < Self.freshWindow ? .here : .tab
    }

    // 시스템은 링크를 받으려고 만든 창을 보이고 곧바로 링크를 넘긴다. 사람이 창을 직접 연 뒤 이렇게 빨리 다른 앱의 링크를
    // 따라가지는 않는다.
    static let freshWindow: TimeInterval = 2
}

extension Workspace {
    func entry(for link: AppLink, hint: UUID? = nil) -> Navigator.Entry? {
        switch link.kind.home {
        case .app:
            return Navigator.Entry(link: link.kind == .settings ? .settings(link.settingsPage ?? SettingsTab.remembered.page) : link)
        case .transcript:
            return transcript.semesters.contains { $0.id == link.id } ? Navigator.Entry(link: link) : nil
        case .catalog:
            return catalog.people.contains { $0.id == link.id } ? Navigator.Entry(link: link) : nil
        case .quiz:
            return course(holdingCard: link.id, hint: hint).map { Navigator.Entry(link: link, course: $0) }
        case .course:
            let files = (hint.flatMap(course).map { [$0] } ?? []) + courses
            return link.course(in: files.map(\.file)).map { Navigator.Entry(link: link, course: $0) }
        }
    }

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
            return [String(localized: .rootNavSettings), link.settingsPage.map { SettingsTab($0).label }].compactMap { $0 }.joined(
                separator: " · ")
        case .semester: return transcript.semesters.first { $0.id == link.id }?.title ?? ""
        case .person: return item ?? String(localized: .rootNavPeople)
        case .course, .session, .unit, .note, .material, .assignment, .exam, .problemSet, .card, .recording: return link.string
        }
    }

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
        case .recording:
            return file.flatMap { f in
                f.recordings.first { $0.id == link.id }.map { RecordingPlayerModel.name(of: $0, in: f, calendar: calendar) }
            }
        case .card: return file.map { _ in CourseSection.quizCards.title }
        }
    }

    func name(of link: AppLink) -> String? {
        guard let entry = link.kind.isPlace ? Navigator.Entry(link: link) : entry(for: link) else { return nil }
        return link.kind == .course ? title(of: entry) : itemName(of: entry) ?? title(of: entry)
    }

    func label(of link: AppLink) -> String? {
        name(of: link).map(link.label)
    }
}

extension AppLink {
    func label(_ name: String) -> String {
        let part: String? =
            switch anchor {
            case .page(let n): String(localized: .notesAssistLinkPage(n))
            case .heading(let heading): heading
            case .block(let block): "^" + block
            case .time(let t): AppLink.clock(t)
            case nil: nil
            }
        return [name, part].compactMap { $0 }.joined(separator: " › ")
    }

    func noteLink(named name: String?) -> String {
        let fragment: String?? =
            switch anchor {
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
        self =
            switch page {
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

@MainActor enum NoteLinks {
    static func open(_ href: String, base: URL?, in placement: LinkPlacement = .here, openNote: (String) -> Void, openLink: OpenLinkAction)
    {
        // web view는 링크를 URL로 넘기면서 블록의 `^`를 escape 하고, 이 escape는 URL로 읽을 때만 풀린다.
        if let link = URL(string: href).flatMap(AppLink.init(url:)) ?? AppLink(string: href) {
            openLink(link, in: placement)
            return
        }
        guard
            let url = URL(string: href, relativeTo: base)
                ?? URL(string: href.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "")
        else { return }
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

    static func isAppLink(_ href: String) -> Bool { AppLink(string: href) != nil }
}

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

    static func placements(multipleWindows: Bool) -> [LinkPlacement] {
        multipleWindows ? LinkPlacement.allCases : [.here, .beside]
    }
}

@MainActor final class PDFLinks: NSObject, PDFViewDelegate {
    private var opener: OpenLinkAction
    private static var key = 0

    private init(opener: OpenLinkAction) { self.opener = opener }

    // `PDFView`는 delegate를 weak로 들고 있으므로, delegate를 view 자체에 붙여 둔다.
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
