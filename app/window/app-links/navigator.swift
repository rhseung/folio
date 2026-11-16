import FolioDomain
import FolioMarkdown
import FolioStorage
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

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
