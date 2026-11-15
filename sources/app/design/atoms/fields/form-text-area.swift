import FolioDomain
import SwiftUI

struct FormTextArea: View {
    let label: String
    var detail: String?
    @Binding var text: String
    @Environment(\.textAreaRoom) private var textAreaRoom

    private static var around: CGFloat { Theme.Space.l + Theme.Space.s + 2 * Theme.Space.m }

    var body: some View {
        Block(label, note: detail) {
            Card(padding: Theme.Space.m) {
                GrowingTextEditor(text: $text, room: textAreaRoom.map { $0 - Self.around })
            }
        }
    }
}
