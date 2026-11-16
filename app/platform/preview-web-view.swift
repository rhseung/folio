import FolioDomain
import FolioMarkdown
import SwiftUI
import WebKit

#if os(macOS)
final class PreviewWebView: WKWebView {
    var toggleMode: (@MainActor () -> Void)?
    weak var page: NotePreviewPage?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "e",
            let toggleMode
        {
            toggleMode()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        let dropped: Set<String> = [
            "WKMenuItemIdentifierReload", "WKMenuItemIdentifierGoBack", "WKMenuItemIdentifierGoForward",
            "WKMenuItemIdentifierOpenLinkInNewWindow", "WKMenuItemIdentifierDownloadLinkedFile", "WKMenuItemIdentifierOpenImageInNewWindow",
            "WKMenuItemIdentifierDownloadImage", "WKMenuItemIdentifierOpenFrameInNewWindow", "WKMenuItemIdentifierInspectElement",
        ]
        for item in menu.items where dropped.contains(item.identifier?.rawValue ?? "") { menu.removeItem(item) }
        if let href = page?.menuHref, let link = AppLink(string: href) {
            addLinkItems(menu, link)
        } else if let note = page?.noteLink, let anchor = page?.menuAnchor, note.with(anchor) != note {
            let link = note.with(anchor)
            menu.insertItem(
                LinkMenuItem(String(localized: anchor.isBlock ? .linkCopyBlock : .linkCopyHeading), symbol: "link") { copyLink(link) },
                at: 0)
            if menu.items.count > 1 { menu.insertItem(.separator(), at: 1) }
        }
        super.willOpenMenu(menu, with: event)
    }

    private func addLinkItems(_ menu: NSMenu, _ link: AppLink) {
        let webKit: Set<String> = ["WKMenuItemIdentifierOpenLink", "WKMenuItemIdentifierCopyLink"]
        for item in menu.items where webKit.contains(item.identifier?.rawValue ?? "") { menu.removeItem(item) }
        var items = LinkPlacement.allCases.map { placement in
            LinkMenuItem(placement.title, symbol: placement.symbol) { [weak self] in self?.page?.open(link.string, in: placement) }
        }
        items.append(LinkMenuItem(String(localized: .linkCopy), symbol: "link") { copyLink(link) })
        for (i, item) in items.enumerated() { menu.insertItem(item, at: i) }
        if menu.items.count > items.count { menu.insertItem(.separator(), at: items.count) }
    }
}
#else
final class PreviewWebView: WKWebView {
    var toggleMode: (@MainActor () -> Void)?
    weak var page: NotePreviewPage?

    // WebKit은 링크와 그림에서만 delegate에 context menu를 묻는다. 제목이나 블록을 길게 누르면 메뉴 대신 낱말이 선택되므로, Mac의 오른쪽 클릭 메뉴처럼 그때 열리는 편집 메뉴의 맨
    // 앞에 그곳의 링크를 넣는다.
    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, let action = Self.anchorAction(page) else { return }
        builder.insertChild(UIMenu(options: .displayInline, children: [action]), atStartOfMenu: .root)
    }

    static func anchorAction(_ page: NotePreviewPage?) -> UIAction? {
        guard let note = page?.noteLink, let anchor = page?.selectionAnchor, note.with(anchor) != note else { return nil }
        let link = note.with(anchor)
        return UIAction(title: String(localized: anchor.isBlock ? .linkCopyBlock : .linkCopyHeading), image: UIImage(systemName: "link")) {
            _ in
            copyLink(link)
        }
    }
}
#endif
