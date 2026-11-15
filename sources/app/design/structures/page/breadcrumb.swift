import FolioDomain
import SwiftUI

struct Breadcrumb: View {
    let crumbs: [Crumb]
    let foldWidth: CGFloat
    let maxWidth: CGFloat
    static let minWidth: CGFloat = 160
    @State private var fullWidth: CGFloat = 0
    @State private var showsHidden = false

    var body: some View {
        let folded = crumbs.count > 2 && fullWidth > foldWidth
        HStack(spacing: Theme.Space.s) {
            if folded, let first = crumbs.first, let last = crumbs.last {
                step(first, at: 0)
                separator
                Button(.designHiddenPath, systemImage: "ellipsis") { showsHidden = true }
                    .buttonStyle(.toolbar)
                    .help(Text(.designHiddenPath))
                    .popover(isPresented: $showsHidden, arrowEdge: .bottom) { hidden }
                    .padding(.horizontal, -Theme.Space.s)
                separator
                step(last, at: crumbs.count - 1)
            } else {
                row
            }
        }
        .lineLimit(1)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background {
            row.fixedSize().hidden().onGeometryChange(for: CGFloat.self, of: \.size.width) { fullWidth = $0 }
        }
    }

    var row: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(crumbs.indices, id: \.self) { i in
                if i > 0 { separator }
                step(crumbs[i], at: i)
            }
        }
    }

    var separator: some View { Text("/").font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.textTertiary) }

    @ViewBuilder func step(_ crumb: Crumb, at i: Int) -> some View {
        let between = i > 0 && i < crumbs.count - 1
        HStack(spacing: Theme.Space.s) {
            if i == 0 {
                if let dot = crumb.dot {
                    CourseMark(icon: crumb.symbol, color: dot)
                } else if let symbol = crumb.symbol {
                    LineIcon(symbol: symbol).foregroundStyle(Theme.Palette.chromeIcon)
                }
            }
            if between, let action = crumb.action {
                Button(crumb.title, action: action).buttonStyle(.pointing(.plain)).help(Text(.designCrumbTopHelp(crumb.title)))
            } else if i == crumbs.count - 1, let rename = crumb.rename {
                Button(crumb.title, action: rename).buttonStyle(.pointing(.plain)).help(Text(.designCrumbRenameHelp))
            } else {
                Text(crumb.title)
            }
        }
        .font(between ? Theme.Typeface.body : Theme.Typeface.bodyStrong)
        .foregroundStyle(between ? Theme.Palette.textSecondary : Theme.Palette.text)
    }

    var hidden: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            ForEach(Array(crumbs.dropFirst().dropLast().enumerated()), id: \.offset) { _, crumb in
                Button {
                    showsHidden = false
                    crumb.action?()
                } label: {
                    ColumnRow(title: crumb.title, symbol: crumb.symbol ?? "folder", chosen: false)
                }
                .buttonStyle(.pointing(.plain))
                .disabled(crumb.action == nil)
            }
        }
        .padding(Theme.Space.s)
        .frame(minWidth: 200)
        .font(Theme.Typeface.body)
    }
}
