import FolioDomain
import FolioMarkdown
import SwiftUI
import WebKit

@MainActor final class PreviewLink {
    weak var page: NotePreviewPage?
    private(set) var last: (line: Int, frac: Double)?

    func follow(line: Int, frac: Double) {
        last = (line, frac)
        refollow()
    }

    func refollow() {
        guard let last else { return }
        page?.follow(line: last.line, frac: last.frac)
    }
}
