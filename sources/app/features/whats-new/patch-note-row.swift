import FolioDomain
import SwiftUI

struct PatchNoteRow: View {
    let item: PatchNotes.Item
    var opening: () -> Void = {}
    @Environment(\.openLink) private var openLink

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(PatchNotes.Kind.allCases, id: \.self) { Chip($0.label, tone: $0.tone).hidden() }
            Chip(item.kind.label, tone: item.kind.tone)
        }
        Text(item.text).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        if let link = item.link {
            Button(.commonOpen) {
                opening()
                openLink(link)
            }
            .buttonStyle(.ghost)
            .contentShape(TouchTarget())
        }
    }
}
