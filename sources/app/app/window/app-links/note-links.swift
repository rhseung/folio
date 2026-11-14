import FolioDomain
import FolioMarkdown
import FolioStorage
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

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
        case "file", LocalFileScheme.scheme:
            // 노트 안의 상대 링크 `[이름](다른 노트.md)`이다. 그 밖의 파일은 이 보기에서 열지 않는다.
            if NoteFormat(path: url.path) == .markdown { openNote(url.deletingPathExtension().lastPathComponent) }
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
