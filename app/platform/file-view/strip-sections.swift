import FolioDomain
import SwiftUI

/// A run of a PDF's pages under one header in a thumbnail column: a class's progress in the page strip (#147), or a
/// unit's zone on the split screen (#321). Both columns lay it out with `StripItem.column` and draw it with the views
/// below, so a section reads the same in either place.
struct StripSection: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A class's pages, or a unit's: a filled dot, and the course-colour line down its pages.
        case held
        /// A unit made when the split is saved: an open dot, as on a range not saved yet, and the line.
        case new
        /// Pages that go to no unit: a grey open dot and no line, as pages with no progress have none.
        case none

        var lined: Bool { self != .none }
    }

    /// The class's or the split section's id.
    let id: UUID
    let pages: ClosedRange<Int>
    /// `10/28(수)`, or the unit's title.
    let title: String
    var kind: Kind = .held

    var label: String { Session.pagesLabel(pages) }
}

/// One page with what heads it, or a folded section's header alone. A header is part of its first page's item rather
/// than an item of its own: scrolled to, the two come into view together. As siblings the header took the page's id,
/// and a jump showed it with the page below.
struct StripItem: Identifiable, Equatable {
    enum Lead: Equatable {
        case header(StripSection, open: Bool)
        /// The section being changed: its header turned into the row its range is changed from.
        case edit(StripSection)
        /// The row a new range is saved from, above its pages.
        case draft(ClosedRange<Int>)
    }

    enum ID: Hashable { case page(Int), folded(UUID) }

    enum Mark: Equatable {
        case plain
        /// In an unfolded section: the course-colour line runs down beside it, ending at the section's last page.
        case line(last: Bool)
        /// In the range being picked or changed.
        case picked
    }

    let lead: Lead?
    let page: Int?
    let mark: Mark

    var id: ID {
        if let page { return .page(page) }
        if case .header(let s, _)? = lead { return .folded(s.id) }
        return .folded(UUID())
    }

    /// The column top to bottom: pages no section holds, each section's header with its pages when unfolded, the
    /// section being changed under its edit row, and a new range under its draft row.
    static func column(pageCount: Int, sections: [StripSection], editing: UUID?, draft: ClosedRange<Int>?,
                       isOpen: (StripSection) -> Bool) -> [StripItem] {
        func run(_ pages: ClosedRange<Int>, lead: Lead, mark: (Int) -> Mark) -> [StripItem] {
            pages.map { StripItem(lead: $0 == pages.lowerBound ? lead : nil, page: $0, mark: mark($0)) }
        }
        var items: [StripItem] = []
        var page = 1
        while page <= pageCount {
            if let s = sections.first(where: { $0.pages.lowerBound == page }) {
                if s.id == editing {
                    items += run(s.pages, lead: .edit(s)) { _ in .picked }
                } else if isOpen(s) {
                    items += run(s.pages, lead: .header(s, open: true)) { s.kind.lined ? .line(last: $0 == s.pages.upperBound) : .plain }
                } else {
                    items.append(StripItem(lead: .header(s, open: false), page: nil, mark: .plain))
                }
                page = s.pages.upperBound + 1
            } else if let draft, draft.lowerBound == page {
                items += run(draft, lead: .draft(draft)) { _ in .picked }
                page = draft.upperBound + 1
            } else {
                items.append(StripItem(lead: nil, page: page, mark: .plain))
                page += 1
            }
        }
        return items
    }
}

enum StripMetrics {
    static let gutter: CGFloat = 32
    static let header: CGFloat = Theme.Size.toolbarButton - Theme.Space.xs
    static let line: CGFloat = 4
    /// From the column's leading edge to the line's middle: under the header's dot, past its chevron.
    static let lineCenter: CGFloat = Theme.Space.s + Theme.Space.m + Theme.Space.xs + Theme.Size.dot / 2
}

/// An item's place in the column: its insets, and its section's line beside a page of an unfolded section, from just
/// under the header's dot on the first page down to above the last page's number. Square where it meets the next
/// page, so the pages' pieces read as one line.
struct StripItemFrame<Content: View>: View {
    let item: StripItem
    @ViewBuilder var content: Content
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.leading, Theme.Space.s)
            .padding(.trailing, Theme.Space.m)
            .background(alignment: .topLeading) { line }
    }

    @ViewBuilder private var line: some View {
        if case .line(let last) = item.mark {
            let first = item.lead != nil
            let round = StripMetrics.line / 2
            UnevenRoundedRectangle(topLeadingRadius: first ? round : 0, bottomLeadingRadius: last ? round : 0,
                                   bottomTrailingRadius: last ? round : 0, topTrailingRadius: first ? round : 0)
                .fill(accent.color)
                .frame(width: StripMetrics.line)
                .padding(.top, first ? StripMetrics.header / 2 + Theme.Size.dot / 2 + Theme.Space.xs : 0)
                .padding(.bottom, last ? Theme.Space.xl : 0)
                .offset(x: StripMetrics.lineCenter - StripMetrics.line / 2)
        }
    }
}

/// The section's dot: filled for pages held, open for pages a save will give, grey and open for pages that go to
/// nothing.
struct StripDot: View {
    let kind: StripSection.Kind
    @Environment(\.accent) private var accent

    var body: some View {
        switch kind {
        case .held: CourseDot(color: accent.color)
        case .new: Circle().strokeBorder(accent.color, lineWidth: 2).frame(width: Theme.Size.dot, height: Theme.Size.dot)
        case .none: Circle().strokeBorder(Theme.Palette.textTertiary, lineWidth: 2).frame(width: Theme.Size.dot, height: Theme.Size.dot)
        }
    }
}

/// A section's one-line header: the fold chevron, then the dot, title and range, which change its range when pressed.
/// The pointer lights the part that does, so a first look finds it.
struct StripHeader: View {
    let section: StripSection
    let open: Bool
    /// Just saved: lit a moment so the eye finds where the row went.
    var lit = false
    let help: Text
    let toggle: () -> Void
    let edit: () -> Void
    @Environment(\.accent) private var accent
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Button { withAnimation(.snappy(duration: 0.2)) { toggle() } } label: {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(Theme.Glyph.small)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: Theme.Space.m, height: StripMetrics.header)
                    .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .help(Text(open ? .commonCollapse : .commonExpand))
            Button(action: edit) {
                HStack(spacing: Theme.Space.tight) {
                    StripDot(kind: section.kind)
                    Text(section.title).font(Theme.Typeface.bodyStrong).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(section.kind == .none ? Theme.Palette.textTertiary : open ? Theme.Palette.text : Theme.Palette.textSecondary)
                    Spacer(minLength: Theme.Space.xs)
                    Text(section.label).font(Theme.Typeface.caption).monospacedDigit().fixedSize().foregroundStyle(Theme.Palette.textSecondary)
                }
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .help(help)
        }
        .frame(height: StripMetrics.header)
        .padding(.trailing, Theme.Space.xs)
        .background(lit ? accent.tint : hovering ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
        .onHover { hovering = $0 }
        .padding(.bottom, open ? Theme.Space.s : Theme.Space.xxs)
    }
}

/// The row a range is changed or saved from, in place of a section's header or above a new range: its dot, what it
/// is, the range, whatever else it asks, [취소][confirm]. Tinted, so the picked pages under it read as its own.
struct StripEditRow<Title: View, Extra: View>: View {
    let kind: StripSection.Kind
    let range: String?
    let confirm: String
    let canConfirm: Bool
    var refusal: String?
    let cancel: () -> Void
    let commit: () -> Void
    @ViewBuilder var title: Title
    @ViewBuilder var extra: Extra
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.tight) {
                StripDot(kind: kind)
                title.lineLimit(1).truncationMode(.tail)
                Spacer(minLength: Theme.Space.xs)
                if let range {
                    Text(range).font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit().fixedSize().foregroundStyle(accent.ink)
                }
            }
            extra
            HStack(spacing: Theme.Space.tight) {
                Button { withAnimation(.snappy(duration: 0.2)) { cancel() } } label: {
                    Text(.commonCancel).frame(maxWidth: .infinity)
                }
                .buttonStyle(.ghost)
                Button { withAnimation(.snappy(duration: 0.2)) { commit() } } label: {
                    Text(confirm).frame(maxWidth: .infinity)
                }
                .buttonStyle(.prominent)
                .disabled(!canConfirm)
            }
            .controlSize(.small)
            if let refusal {
                Text(refusal).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.s)
        // Its dot under the headers' dots, past where their chevrons stand.
        .padding(.leading, StripMetrics.lineCenter - Theme.Size.dot / 2 - Theme.Space.s * 2)
        .background(accent.tint, in: .rect(cornerRadius: Theme.Radius.control))
        .padding(.bottom, Theme.Space.m)
        .transition(.opacity)
    }
}

/// A page of the column, pressed as both columns take it: a press goes to the page; ⇧-press on a Mac, or a tap while
/// a range is up on a touch screen, which has no ⇧ to hold, moves a range's end; a long press starts one.
struct StripPage: View {
    let controller: PDFController
    let page: Int
    let picked: Bool
    let gutter: Bool
    /// A range is up: on a touch screen the next tap moves its end.
    let ranging: Bool
    let press: (_ page: Int, _ extend: Bool) -> Void
    let start: (_ page: Int) -> Void

    var body: some View {
        PageThumbnail(thumbnails: controller.thumbnails, page: page, current: controller.page + 1 == page, picked: picked)
            .padding(.leading, gutter ? StripMetrics.gutter : Theme.Space.xs)
            .padding(.bottom, Theme.Space.s)
            .contentShape(.rect)
            #if os(macOS)
            .gesture(TapGesture().modifiers(.shift).onEnded { pick(extend: true) }
                .exclusively(before: TapGesture().onEnded { pick(extend: false) }))
            #else
            .onTapGesture { pick(extend: ranging) }
            .onLongPressGesture { start(page) }
            #endif
            .pointingHand()
    }

    private func pick(extend: Bool) {
        press(page, extend)
        controller.go(to: page - 1)
    }
}
