import FolioActions
import FolioDomain
import SwiftUI

struct SessionSlot: View {
    static let width: CGFloat = 56
    static var empty: some View { Color.clear.frame(width: width, height: 1) }

    let title: String
    let symbol: String
    var tint: Color = Theme.Palette.textSecondary
    let help: String
    var fixed = true
    let action: () -> Void

    init(
        _ title: String, symbol: String, tint: Color = Theme.Palette.textSecondary, help: String, fixed: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.help = help
        self.fixed = fixed
        self.action = action
    }

    var body: some View {
        Button(title, systemImage: symbol, action: action)
            .buttonStyle(.ghost)
            .tint(tint)
            .help(help)
            .frame(width: fixed ? Self.width : nil, alignment: .trailing)
    }
}
