#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import FolioFixtures
import PDFKit
import SwiftUI

struct MenuPicture: View {
    let rows: [MenuRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                if i > 0 && rows[i - 1].group.band != row.group.band {
                    Theme.Palette.lineSoft.frame(height: 1).padding(.vertical, Theme.Space.xs).padding(.horizontal, Theme.Space.s)
                }
                line(row)
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .frame(width: 280)
        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.line))
        .padding(Theme.Space.xl)
        .background(Theme.Palette.page)
    }

    func line(_ row: MenuRow) -> some View {
        let checked: Bool, submenu: Bool
        switch row.kind {
        case .check(let on, _): (checked, submenu) = (on, false)
        case .submenu, .share: (checked, submenu) = (false, true)
        case .action: (checked, submenu) = (false, false)
        }
        return HStack(spacing: Theme.Space.s) {
            Image(systemName: "checkmark").font(Theme.Glyph.small).opacity(checked ? 1 : 0).frame(width: 12)
            Image(systemName: row.symbol).frame(width: 16)
            Text(row.title)
            Spacer(minLength: Theme.Space.xl)
            if submenu { Image(systemName: "chevron.right").font(Theme.Glyph.small) }
        }
        .font(Theme.Typeface.body)
        .foregroundStyle(row.role == .destructive ? Theme.Palette.danger : row.disabled ? Theme.Palette.textTertiary : Theme.Palette.text)
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 24)
    }
}
#endif
