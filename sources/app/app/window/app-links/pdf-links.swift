import FolioDomain
import FolioMarkdown
import FolioStorage
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

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
