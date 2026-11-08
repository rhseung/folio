import FolioDomain
import PDFKit
import SwiftUI

/// The split screen (#321): a lecture's pages down the left in its sections, the page itself in the middle, and the
/// section bar with a row per section on the right. The column heads each section as the page strip heads a class's
/// progress, and changes its pages the same way; a gap between two thumbnails cuts a section there, or joins two. The
/// rows say which unit each section goes to. Saving writes the whole split in one `material split`.
struct LectureSplitPane: View {
    let controller: PDFController
    @Binding var split: LectureSplit
    let units: [FolioDomain.Unit]
    let note: String?
    let save: () -> Void
    let cancel: () -> Void
    @State private var strip = SplitStrip()

    var body: some View {
        HStack(spacing: 0) {
            SplitThumbnails(controller: controller, split: $split, strip: $strip, name: name)
                .frame(width: PageStrip.lectureColumn)
            Theme.Palette.lineSoft.frame(width: 1)
            PDFKitView(controller: controller)
            Theme.Palette.lineSoft.frame(width: 1)
            panel.frame(width: Self.panel)
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.splitEdit) { _, edit in
            guard let edit, split.sections.indices.contains(edit.section) else { return }
            strip.edit(split.sections[edit.section].id, in: split)
            strip.extend(to: edit.page, in: &split)
            // Up to the section's first page from past its end, so its edit row lands at the top with its pages under it.
            guard let i = strip.index(in: split) else { return }
            let first = split.sections[i].firstPage, last = split.sections[i].lastPage
            Task {
                controller.go(to: last - 1)
                try? await Task.sleep(for: .seconds(0.5))
                controller.go(to: first - 1)
            }
        }
        #endif
    }

    /// Cancel and save on the title's line. The Claude button floats over the pane's bottom corner and takes no room
    /// in it, so the main actions stay out of that corner rather than the pane making way for it.
    private var panel: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.s) {
                Text(.fileViewSplitTitle).font(Theme.Typeface.sectionTitle).foregroundStyle(Theme.Palette.textSecondary)
                Spacer(minLength: Theme.Space.s)
                Button(String(localized: .commonCancel), action: cancel).buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button(String(localized: .commonSave), action: save).buttonStyle(.prominent).keyboardShortcut(.defaultAction)
            }
            // Ends where the bar and rows under it end, not nearer the pane's edge: the column's content edge is one line.
            .padding(.horizontal, Theme.Space.l)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionEditor(split: $split, units: units, page: controller.page + 1, selected: selected) { controller.go(to: $0 - 1) }
                    if let note {
                        Text(note).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
            }
            .overflowFade(.vertical)
        }
        .padding(.vertical, Theme.Space.l)
    }

    /// The section picked on the bar and in the rows is the one the column is changing.
    private var selected: Binding<Int?> {
        Binding(get: { strip.index(in: split) }, set: { i in
            if let i, split.sections.indices.contains(i) { strip.edit(split.sections[i].id, in: split) } else { strip.done() }
        })
    }

    static let panel: CGFloat = 400

    /// What a section reads as: its unit's title, a new unit's name, what the file calls it, or "이름 없는 구역".
    private func name(_ i: Int) -> String {
        let s = split.sections[i]
        let unit = s.unit.flatMap { u in s.isNew ? s.title : units.first { $0.id == u }?.title ?? s.title } ?? ""
        let own = unit.isEmpty ? s.title : unit
        return own.isEmpty ? String(localized: .designSectionsUnnamed) : own
    }
}

/// Every page small, in its section under the section's header; between two pages, a press cuts there, and between
/// two sections joins them.
private struct SplitThumbnails: View {
    let controller: PDFController
    @Binding var split: LectureSplit
    @Binding var strip: SplitStrip
    let name: (Int) -> String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(strip.items(split, name: name)) { item in
                        StripItemFrame(item: item) {
                            lead(item)
                            page(item)
                        }
                            .id(item.id)
                    }
                }
                .padding(.vertical, Theme.Space.s)
            }
            .overflowFade(.vertical)
            .onChange(of: controller.page) { _, page in
                withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(strip.itemID(showing: page + 1, in: split)) }
            }
        }
        .animation(.snappy(duration: 0.2), value: strip.items(split, name: name))
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: split.sections.map(\.pages))
        #endif
    }

    @ViewBuilder private func lead(_ item: StripItem) -> some View {
        switch item.lead {
        case .header(let section, let open)?:
            StripHeader(section: section, open: open, help: Text(.fileViewSplitEditHelp),
                        toggle: { strip.toggle(section.id) }, edit: { strip.edit(section.id, in: split) })
        case .edit(let section)?:
            StripEditRow(kind: section.kind, range: section.label, confirm: String(localized: .fileViewSplitApply),
                         canConfirm: strip.changed(split), cancel: { strip.cancel(&split) }, commit: { strip.done() }) {
                Text(section.title).font(Theme.Typeface.bodyStrong)
                    .foregroundStyle(section.kind == .none ? Theme.Palette.textTertiary : Theme.Palette.text)
            } extra: {
                EmptyView()
            }
        case .draft?, nil:
            EmptyView()
        }
    }

    @ViewBuilder private func page(_ item: StripItem) -> some View {
        if let page = item.page {
            StripPage(controller: controller, page: page, picked: item.mark == .picked, gutter: true, ranging: strip.editing != nil,
                      press: { page, extend in
                          if extend { strip.extend(to: page, in: &split) } else { strip.press(page) }
                      },
                      start: { strip.start(at: $0, in: split) })
                .overlay(alignment: .bottom) {
                    if page < split.pageCount { gap(after: page) }
                }
        }
    }

    private func gap(after page: Int) -> some View {
        let i = split.section(at: page)
        let boundary = split.sections[i].lastPage == page
        return Gap(boundary: boundary) {
            if boundary { split.merge(after: i) } else { split.split(at: page + 1) }
        }
        .padding(.leading, StripMetrics.gutter)
    }
}

private struct Gap: View {
    let boundary: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            // Only under the pointer: the next section's header already marks where a section ends.
            if hovering {
                Rectangle()
                    .fill(boundary ? accent.color : Theme.Palette.textTertiary)
                    .frame(height: boundary ? 2 : 1)
                    .padding(.horizontal, Theme.Space.m)
                Image(systemName: boundary ? "arrow.up.and.down.and.arrow.left.and.right" : "scissors")
                    .font(Theme.Glyph.small)
                    .foregroundStyle(boundary ? accent.ink : Theme.Palette.textSecondary)
                    .padding(Theme.Space.xxs)
                    .background(Theme.Palette.card, in: .circle)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Space.s)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .pointingHand()
        .help(Text(boundary ? .fileViewSplitJoinHelp : .fileViewSplitCutHelp))
    }
}
