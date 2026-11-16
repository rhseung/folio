import FolioDomain
import FolioStorage
import SwiftUI

struct OpenElsewhereButton: View {
    let url: URL
    var prominent = false

    var body: some View {
        #if os(macOS)
        if prominent {
            Button(.materialsOpenWithDefault) { NSWorkspace.shared.open(url) }.buttonStyle(.prominent)
        } else {
            Button(.materialsOpenWithDefault, systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                .help(Text(.materialsOpenWithDefault))
        }
        #else
        if prominent {
            ShareLink(item: url) { Text(.fileViewShare) }.buttonStyle(.prominent)
        } else {
            ShareLink(item: url) { Label(String(localized: .fileViewShare), systemImage: "square.and.arrow.up") }
        }
        #endif
    }
}
