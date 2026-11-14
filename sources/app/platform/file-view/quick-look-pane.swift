import QuickLook
import SwiftUI

#if os(macOS)
import Quartz
#endif

struct QuickLookPane {
    let url: URL
}

#if os(macOS)
extension QuickLookPane: NSViewRepresentable {
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.shouldCloseWithWindow = false
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }

    // preview view를 열어 두면 그 생성기의 프로세스가 계속 돈다.
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}
#else
extension QuickLookPane: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Source { Source(url: url) }

    final class Source: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
#endif
