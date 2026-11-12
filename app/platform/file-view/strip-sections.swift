import FolioDomain
import SwiftUI

/// A run of a PDF's pages under one header in a thumbnail column: a class's progress in the page strip (#147), or a
/// unit's zone on the split screen (#321). Both columns lay it out with `StripItem.column` and draw it with the views
/// below, so a section reads the same in either place.
struct StripSection: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A class's pages, or a unit's: on the course's tint, under a course-colour chevron.
        case held
        /// A unit made when the split is saved: on the tint too, its name in the course's ink as a range not saved yet
        /// names itself.
        case new
        /// Pages that go to no unit: no tint and a grey chevron, as pages with no progress have neither.
        case none

        var tinted: Bool { self != .none }
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
        /// On its section's tint, which ends under the section's last page, or under a folded section's header.
        case tinted(last: Bool)
        /// In the range being picked or changed.
        case picked
    }

    let lead: Lead?
    let page: Int?
    let mark: Mark
    /// Under the page: a new range's row when it was picked downward, at the end ⇧ set.
    var trail: Lead? = nil

    var id: ID {
        if let page { return .page(page) }
        if case .header(let s, _)? = lead { return .folded(s.id) }
        return .folded(UUID())
    }

    /// The column top to bottom: pages no section holds, each section's header with its pages when unfolded, the
    /// section being changed under its edit row, and a new range with its draft row over it, or under it when
    /// `draftBelow`.
    static func column(pageCount: Int, sections: [StripSection], editing: UUID?, draft: ClosedRange<Int>?, draftBelow: Bool = false,
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
                    items += run(s.pages, lead: .header(s, open: true)) { s.kind.tinted ? .tinted(last: $0 == s.pages.upperBound) : .plain }
                } else {
                    items.append(StripItem(lead: .header(s, open: false), page: nil, mark: s.kind.tinted ? .tinted(last: true) : .plain))
                }
                page = s.pages.upperBound + 1
            } else if let draft, draft.lowerBound == page {
                if draftBelow {
                    items += draft.map { StripItem(lead: nil, page: $0, mark: .picked, trail: $0 == draft.upperBound ? .draft(draft) : nil) }
                } else {
                    items += run(draft, lead: .draft(draft)) { _ in .picked }
                }
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
    /// A header's row: a finger's height on a touch screen, where it is what a range is changed from.
    #if os(iOS)
    static let header: CGFloat = 44
    #else
    static let header: CGFloat = Theme.Size.toolbarButton - Theme.Space.xs
    #endif
}

/// An item's place in the column, and its piece of its section's tint. The pieces of a section meet square and round
/// only at its header's top and under its last page, so an unfolded section reads as one surface from its header down.
/// Every page sits in the column's middle, so crossing into or out of a section moves no thumbnail sideways.
struct StripItemFrame<Content: View>: View {
    let item: StripItem
    @ViewBuilder var content: Content
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background { tint }
            .padding(.horizontal, Theme.Space.s)
    }

    @ViewBuilder private var tint: some View {
        if case .tinted(let last) = item.mark {
            let first = item.lead != nil
            let r = Theme.Radius.strip
            UnevenRoundedRectangle(topLeadingRadius: first ? r : 0, bottomLeadingRadius: last ? r : 0,
                                   bottomTrailingRadius: last ? r : 0, topTrailingRadius: first ? r : 0)
                .fill(accent.tint)
                // Short of the gap under the last page, or under a folded header, so the next item stands apart.
                .padding(.bottom, last ? Theme.Space.xs : 0)
        }
    }
}

/// A section's one-line header: the fold chevron in the course's colour where it is tinted, then the title and range,
/// which change its range when pressed. The pointer lights the part that does, so a first look finds it.
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
            Button { withAnimation(Theme.Motion.quick) { toggle() } } label: {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(Theme.Glyph.small)
                    .foregroundStyle(section.kind.tinted ? accent.ink : Theme.Palette.textTertiary)
                    .frame(width: Theme.Space.m, height: StripMetrics.header)
                    .padding(.leading, Theme.Space.tight)
                    .chevronReach()
            }
            .buttonStyle(.pointing(.plain))
            .help(Text(open ? .commonCollapse : .commonExpand))
            Button(action: edit) {
                HStack(spacing: Theme.Space.xs) {
                    Text(section.title).font(Theme.Typeface.bodyStrong).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(titleColor)
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
        .padding(.trailing, Theme.Space.s)
        .background(lit ? accent.tint : hovering ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.strip))
        .onHover { hovering = $0 }
        .padding(.bottom, open ? Theme.Space.s : Theme.Space.xs)
    }

    private var titleColor: Color {
        switch section.kind {
        case .held: open ? Theme.Palette.text : Theme.Palette.textSecondary
        case .new: accent.ink
        case .none: Theme.Palette.textTertiary
        }
    }
}

private extension View {
    /// On a touch screen the chevron's press reaches out over the column's margin to its edge, the one side with
    /// nothing else to press.
    @ViewBuilder func chevronReach() -> some View {
        #if os(iOS)
        padding(.leading, Theme.Space.s).contentShape(.rect).padding(.leading, -Theme.Space.s)
        #else
        contentShape(.rect)
        #endif
    }
}

/// The edit row's dot, under where the headers' chevrons stand: filled for pages held, open for pages a save will
/// give, grey and open for pages that go to nothing.
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

/// The row a range is changed or saved from, in place of a section's header or at a new range's end: its dot and what
/// it is, the range on a line of its own (the column is too narrow for "11/4(수) 오늘 19–21쪽" on one), whatever
/// else it asks, [취소][confirm]. Tinted and ringed in the course's colour: the tint alone read as one more section
/// beside a section's own.
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
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.tight) {
                    StripDot(kind: kind)
                    title.lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                if let range {
                    Text(range).font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit().foregroundStyle(accent.ink)
                        .padding(.leading, Theme.Size.dot + Theme.Space.tight)
                }
            }
            extra
            HStack(spacing: Theme.Space.tight) {
                Button { withAnimation(Theme.Motion.quick) { cancel() } } label: {
                    Text(.commonCancel).frame(maxWidth: .infinity)
                }
                .buttonStyle(.ghost)
                Button { withAnimation(Theme.Motion.quick) { commit() } } label: {
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
        // Its dot under the headers' chevrons.
        .padding(Theme.Space.s)
        .background(accent.tint, in: .rect(cornerRadius: Theme.Radius.strip))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.strip).strokeBorder(accent.color, lineWidth: 1))
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
    let box: CGSize
    /// A range is up: on a touch screen the next tap moves its end.
    let ranging: Bool
    let press: (_ page: Int, _ extend: Bool) -> Void
    /// Nil where the long press opens the page's menu instead, which then holds the way in.
    let start: ((_ page: Int) -> Void)?

    var body: some View {
        PageThumbnail(thumbnails: controller.thumbnails, page: page, current: controller.page + 1 == page, picked: picked, box: box)
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.Space.s)
            .contentShape(.rect)
            #if os(macOS)
            .gesture(TapGesture().modifiers(.shift).onEnded { pick(extend: true) }
                .exclusively(before: TapGesture().onEnded { pick(extend: false) }))
            #else
            .onTapGesture { pick(extend: ranging) }
            .modifier(LongPressStart(start: start.map { start in { start(page) } }))
            #endif
            .pointingHand()
    }

    private func pick(extend: Bool) {
        press(page, extend)
        controller.go(to: page - 1)
    }
}

#if os(iOS)
/// None at all where there's a menu: an empty long press would still race the menu's own.
private struct LongPressStart: ViewModifier {
    let start: (() -> Void)?

    func body(content: Content) -> some View {
        if let start { content.onLongPressGesture(perform: start) } else { content }
    }
}
#endif
