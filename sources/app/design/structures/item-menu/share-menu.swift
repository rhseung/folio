import FolioDomain
import SwiftUI

struct ShareMenu: View {
    let link: AppLink
    var course: UUID?
    @Environment(\.openLink) private var openLink
    @Environment(\.supportsMultipleWindows) private var multipleWindows

    var body: some View {
        Menu {
            ForEach(LinkMenu.placements(multipleWindows: multipleWindows).filter { $0 != .here }, id: \.self) { placement in
                Button(placement.title, systemImage: placement.symbol) { openLink(link, in: placement, course: course) }
            }
            Divider()
            Button(.linkCopy, systemImage: "link") { copyLink(link) }
        } label: {
            Label(.menuShare, systemImage: "square.and.arrow.up")
        }
    }
}
