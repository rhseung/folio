import FolioDomain
import FolioMarkdown
import SwiftUI
import WebKit

#if os(macOS)
@MainActor final class LinkMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(_ title: String, symbol: String, run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { run() }
}
#endif
