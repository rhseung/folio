import FolioDomain
import SwiftUI

struct Block<Content: View, Trailing: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            BlockHeading {
                heading
                if let note { noteText(note) } else { Color.clear.frame(width: 0, height: 0) }
                action
            }
            content
        }
    }
}

extension Block {
    var heading: some View {
        Text(title).font(Theme.Typeface.sectionTitle).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
    }

    // `BlockHeading`이 늘 하위 뷰 하나를 받도록, 비었거나 여러 뷰여도 stack에 담는다.
    var action: some View { HStack(spacing: Theme.Space.s) { trailing }.font(Theme.Typeface.caption).lineLimit(1).fixedSize() }

    func noteText(_ note: String) -> some View {
        Text(note).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
    }
}

extension Block where Trailing == EmptyView {
    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, note: note, trailing: { EmptyView() }, content: content)
    }
}
