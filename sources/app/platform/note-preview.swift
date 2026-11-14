import FolioDomain
import FolioMarkdown
import SwiftUI
import WebKit

struct NotePreview {
    var text: String
    var baseURL: URL?
    var math: MathSyntax = .latex
    var openNote: (String) -> Void = { _ in }
    var anchor: AppLink.Anchor?
    var noteLink: AppLink?
    var edit: (@MainActor (_ from: Int, _ to: Int, _ old: String, _ new: String) -> Bool)?
    var link: PreviewLink?
    var toggleMode: (@MainActor () -> Void)?
    var embeds: NoteEmbedSource?
    var revision = 0
    var views: NoteViews?

    @MainActor final class Coordinator {
        let page = NotePreviewPage.take()
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator() }

    // `enabled`가 false이면 앞 탭 뒤에 남겨 둔 탭이므로, 이 페이지가 ⌘E를 받으면 안 된다. 웹 뷰는 SwiftUI의 비활성 버튼이 거절하기 전에 키를 먼저 받는다.
    @MainActor func update(
        _ page: NotePreviewPage, accent: CourseAccent, dark: Bool, openLink: OpenLinkAction = OpenLinkAction(), enabled: Bool = true
    ) {
        page.openNote = openNote
        page.openLink = openLink
        page.noteLink = noteLink
        page.edit = edit
        page.toggleMode = enabled ? toggleMode : nil
        page.embeds = embeds
        if link?.page !== page { link?.page = page }
        page.link = link
        page.views = views
        if views?.page !== page { views?.page = page }
        page.show(text, baseURL: baseURL, math: math, accent: accent, dark: dark, revision: revision)
        page.reveal(anchor)
    }
}

#if os(macOS)
extension NotePreview: NSViewRepresentable {
    func makeNSView(context: Context) -> PreviewWebView {
        update(
            context.coordinator.page, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink, enabled: context.environment.isEnabled)
        return context.coordinator.page.view
    }

    func updateNSView(_ view: PreviewWebView, context: Context) {
        update(
            context.coordinator.page, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink, enabled: context.environment.isEnabled)
    }

    static func dismantleNSView(_ view: PreviewWebView, coordinator: Coordinator) { coordinator.page.recycle() }
}
#else
extension NotePreview: UIViewRepresentable {
    func makeUIView(context: Context) -> PreviewWebView {
        update(
            context.coordinator.page, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink)
        return context.coordinator.page.view
    }

    func updateUIView(_ view: PreviewWebView, context: Context) {
        update(
            context.coordinator.page, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink)
    }

    static func dismantleUIView(_ view: PreviewWebView, coordinator: Coordinator) { coordinator.page.recycle() }
}
#endif
#if os(iOS)
extension NotePreviewPage: WKUIDelegate {
    func webView(_ webView: WKWebView, contextMenuConfigurationFor element: WKContextMenuElementInfo) async -> UIContextMenuConfiguration? {
        guard let url = element.linkURL, let link = AppLink(url: url) else { return nil }
        let placements = LinkMenu.placements(multipleWindows: UIApplication.shared.supportsMultipleScenes)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let open = placements.map { placement in
                UIAction(title: placement.title, image: UIImage(systemName: placement.symbol)) { _ in self?.open(link.string, in: placement)
                }
            }
            let copy = UIAction(title: String(localized: .linkCopy), image: UIImage(systemName: "link")) { _ in copyLink(link) }
            return UIMenu(children: [UIMenu(options: .displayInline, children: open), copy])
        }
    }
}
#endif
