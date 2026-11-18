import FolioDomain
import SwiftUI
import WebKit

// 애셋 서랍의 크게 보기에서 위젯 하나를 돌린다. 폭은 시트를 따르고, 높이는 위젯이 알린 높이를 `height`로 돌려준다.
struct WidgetPageView {
    let id: NoteWidget.ID
    let noteFolder: URL
    @Binding var height: CGFloat
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    @MainActor final class Coordinator {
        let page = WidgetPage()
        var loaded: NoteWidget.ID?
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor private func update(_ coordinator: Coordinator) {
        let page = coordinator.page
        page.appear(dark: colorScheme == .dark)
        page.resized = { new in if abs(new - height) > 0.5 { height = new } }
        guard coordinator.loaded != id else { return }
        coordinator.loaded = id
        Task { await page.load(id, noteFolder: noteFolder, accent: accent) }
    }
}

#if os(macOS)
extension WidgetPageView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { context.coordinator.page.view }
    func updateNSView(_ view: WKWebView, context: Context) { update(context.coordinator) }
}
#else
extension WidgetPageView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { context.coordinator.page.view }
    func updateUIView(_ view: WKWebView, context: Context) { update(context.coordinator) }
}
#endif
