import FolioDomain
import FolioMarkdown
import SwiftUI

#if os(macOS)
final class HintLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
