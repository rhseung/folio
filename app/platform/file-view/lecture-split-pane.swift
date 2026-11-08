import FolioDomain
import PDFKit
import SwiftUI

/// The split screen (#321): a lecture's pages down the left with its zones over them, the page itself in the middle,
/// and the section bar with a row per zone on the right. A gap between two thumbnails is where a zone is cut, or joined
/// again; the rows say which unit each zone goes to. Saving writes the whole split in one `material split`.
struct LectureSplitPane: View {
    let controller: PDFController
    @Binding var split: LectureSplit
    let units: [FolioDomain.Unit]
    let note: String?
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SplitThumbnails(controller: controller, split: $split, label: label)
                .frame(width: Self.column)
            Theme.Palette.lineSoft.frame(width: 1)
            PDFKitView(controller: controller)
            Theme.Palette.lineSoft.frame(width: 1)
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(.fileViewSplitTitle).font(Theme.Typeface.sectionTitle).foregroundStyle(Theme.Palette.textSecondary)
                ScrollView {
                    SectionEditor(split: $split, units: units, page: controller.page + 1) { controller.go(to: $0 - 1) }
                }
                .overflowFade(.vertical)
                if let note { Text(note).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Spacer()
                    Button(String(localized: .commonCancel), action: cancel).buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                    Button(String(localized: .commonSave), action: save).buttonStyle(.prominent).keyboardShortcut(.defaultAction)
                }
                .clearOfClaudeButton(inset: Theme.Space.l)
            }
            .padding(Theme.Space.l)
            .frame(width: Self.panel)
        }
    }

    static let column: CGFloat = 176
    static let panel: CGFloat = 400

    private func label(_ i: Int) -> String {
        let s = split.sections[i]
        guard let unit = s.unit else { return "" }
        return s.isNew ? s.title : units.first { $0.id == unit }?.title ?? s.title
    }
}

/// Every page small, with each zone's name over its first page. Between two pages, a press cuts there; between two
/// zones, it joins them.
private struct SplitThumbnails: View {
    let controller: PDFController
    @Binding var split: LectureSplit
    let label: (Int) -> String
    @Environment(\.accent) private var accent

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // A page is one view with its zone's header: scrolled to, the header and the page come into view
                    // together. As siblings the header took the page's id, and a jump showed it with the page below.
                    ForEach(1...split.pageCount, id: \.self) { page in
                        let zone = split.section(at: page)
                        VStack(alignment: .leading, spacing: 0) {
                            if split.sections[zone].firstPage == page { header(zone) }
                            PageThumbnail(thumbnails: controller.thumbnails, page: page, current: controller.page + 1 == page)
                                .padding(.horizontal, Theme.Space.m)
                                .background(alignment: .leading) {
                                    // The zone's band down the left edge, so a long zone still reads as one.
                                    (split.sections[zone].unit == nil ? Theme.Palette.fill : accent.color.opacity(zone % 2 == 0 ? Theme.Opacity.onTint : Theme.Opacity.zonePicked))
                                        .frame(width: 4)
                                }
                                .contentShape(.rect)
                                .onTapGesture { controller.go(to: page - 1) }
                            if page < split.pageCount { gap(after: page) }
                        }
                    }
                }
                .padding(.vertical, Theme.Space.s)
            }
            .overflowFade(.vertical)
            .onChange(of: controller.page) { _, page in withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(page + 1) } }
        }
    }

    private func header(_ i: Int) -> some View {
        let s = split.sections[i]
        let name = label(i)
        return HStack(spacing: Theme.Space.xs) {
            Text(name.isEmpty ? String(localized: .designSectionsUnnamed) : name)
                .font(Theme.Typeface.label)
                .foregroundStyle(name.isEmpty ? Theme.Palette.textTertiary : accent.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(s.firstPage == s.lastPage ? "\(s.firstPage)" : "\(s.firstPage)–\(s.lastPage)")
                .font(Theme.Typeface.label.weight(.regular)).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(EdgeInsets(top: Theme.Space.s, leading: Theme.Space.m, bottom: Theme.Space.xs, trailing: Theme.Space.m))
    }

    private func gap(after page: Int) -> some View {
        Gap(boundary: split.sections[split.section(at: page)].lastPage == page) {
            if split.sections[split.section(at: page)].lastPage == page {
                split.merge(after: split.section(at: page))
            } else {
                split.split(at: page + 1)
            }
        }
    }
}

private struct Gap: View {
    let boundary: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            if hovering || boundary {
                Rectangle()
                    .fill(boundary ? accent.color : Theme.Palette.textTertiary)
                    .frame(height: boundary ? 2 : 1)
                    .padding(.horizontal, Theme.Space.m)
            }
            if hovering {
                Image(systemName: boundary ? "arrow.up.and.down.and.arrow.left.and.right" : "scissors")
                    .font(Theme.Glyph.small)
                    .foregroundStyle(boundary ? accent.ink : Theme.Palette.textSecondary)
                    .padding(Theme.Space.xxs)
                    .background(Theme.Palette.card, in: .circle)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 12)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .pointingHand()
        .help(Text(boundary ? .fileViewSplitJoinHelp : .fileViewSplitCutHelp))
    }
}
