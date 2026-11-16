import FolioDomain
import SwiftUI

#if os(macOS)
final class SourceFileTextView: NSTextView {
    var unmarked: () -> Void = {}
    var linkOpener = OpenLinkAction()

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let window, textStorage?.length ?? 0 > 0 {
            let i = characterIndex(for: window.convertPoint(toScreen: event.locationInWindow))
            if i != NSNotFound, openLink(at: i) { return }
        }
        super.mouseDown(with: event)
    }

    func openLink(at i: Int) -> Bool {
        guard let link = AppLink.link(in: string, at: i) else { return false }
        linkOpener(link)
        return true
    }

    override func unmarkText() {
        super.unmarkText()
        unmarked()
    }
}
#else
final class SourceFileTextView: UITextView {
    var unmarked: () -> Void = {}

    override func unmarkText() {
        super.unmarkText()
        unmarked()
    }
}
#endif
