import FolioDomain
import FolioMarkdown
import FolioStorage
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentValues {
    @Entry var openLink = OpenLinkAction()
    @Entry var place: Navigator.Entry?
}

extension Workspace {
    func entry(for link: AppLink, hint: UUID? = nil) -> Navigator.Entry? {
        switch link.kind.home {
        case .app:
            return Navigator.Entry(link: link.kind == .settings ? .settings(link.settingsPage ?? .remembered) : link)
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
        case .today, .grades, .requirements, .people, .codes, .whatsNew, .proposals: return link.kind.place?.title ?? ""
        case .settings: return [link.kind.place?.title, link.settingsPage?.label].compactMap { $0 }.joined(separator: " · ")
        case .semester: return transcript.semesters.first { $0.id == link.id }?.title ?? ""
        case .person: return item ?? String(localized: .rootNavPeople)
        case .course, .session, .unit, .note, .material, .assignment, .exam, .problemSet, .card, .recording: return link.string
        }
    }

    func itemName(of entry: Navigator.Entry) -> String? { linkName(of: entry)?.text }

    func linkName(of entry: Navigator.Entry) -> LinkName? {
        LinkName(entry.link, in: entry.course.flatMap(course)?.file, people: catalog.people, calendar: calendar)
    }

    func name(of link: AppLink) -> String? {
        guard let entry = link.kind.isPlace ? Navigator.Entry(link: link) : entry(for: link) else { return nil }
        return link.kind == .course ? title(of: entry) : itemName(of: entry) ?? title(of: entry)
    }

    func label(of link: AppLink) -> String? {
        name(of: link).map(link.label)
    }
}

extension LinkName {
    var text: String {
        switch self {
        case .item(let name): name
        case .replay(let day?): String(localized: .recordingPageNamed(day))
        case .replay(nil): String(localized: .recordingPage)
        case .page(let page): page.title
        }
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
