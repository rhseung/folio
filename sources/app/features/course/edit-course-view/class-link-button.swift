import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct ClassLinkButton: View {
    @Binding var link: String?
    @State private var open = false

    var body: some View {
        let has = !(link ?? "").isEmpty
        Button(String(localized: .classTimesLink), systemImage: has ? "video.fill" : "video") { open = true }
            .buttonStyle(.ghostIcon)
            .tint(has ? Theme.Palette.text : Theme.Palette.textTertiary)
            .help(link.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: .classTimesLinkHelp))
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(.classTimesLink).font(Theme.Typeface.bodyStrong)
                    TextField(
                        String(localized: .classTimesLinkPrompt), text: Binding(get: { link ?? "" }, set: { link = OnlineLink.stored($0) })
                    )
                    .pill(width: 288)
                    Text(.classTimesLinkHelp).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(Theme.Space.l)
                .frame(width: 320)
            }
    }
}
