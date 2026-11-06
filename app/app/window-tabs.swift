import FolioDomain
import SwiftUI

/// One window's tabs, each with its own history. The window draws them in its toolbar row itself rather than as
/// AppKit window tabs, whose bar took a row of its own over the frame.
@MainActor @Observable
final class WindowTabs {
    private(set) var strip: TabStrip<UUID>
    private var navigators: [UUID: Navigator]
    /// Closing the last tab closes the window, which the window hands over once it has one.
    @ObservationIgnored var closeWindow: @MainActor () -> Void = {}

    init(_ first: Navigator) {
        let id = UUID()
        strip = TabStrip(id)
        navigators = [id: first]
    }

    var selected: UUID { strip.selected }
    var ids: [UUID] { strip.tabs }
    var count: Int { strip.tabs.count }
    var current: Navigator { navigators[strip.selected] ?? Navigator() }

    func navigator(_ id: UUID) -> Navigator? { navigators[id] }

    func open(_ navigator: Navigator = Navigator()) {
        let id = UUID()
        navigators[id] = navigator
        strip.open(id)
    }

    func select(_ id: UUID) { strip.select(id) }
    func select(number n: Int) { strip.select(number: n) }
    func selectNext() { strip.selectNext() }
    func selectPrevious() { strip.selectPrevious() }
    func move(_ id: UUID, to index: Int) { strip.move(id, to: index) }

    func close(_ id: UUID) {
        if strip.close(id) { navigators[id] = nil } else { closeWindow() }
    }

    func closeSelected() { close(selected) }

    func closeOthers(than id: UUID) {
        strip.closeOthers(than: id)
        navigators = navigators.filter { $0.key == id }
    }

    /// Takes a tab out for a window of its own; nil for the last one, which is the window already.
    func take(_ id: UUID) -> Navigator? {
        guard count > 1, let navigator = navigators[id], strip.close(id) else { return nil }
        navigators[id] = nil
        return navigator
    }
}

extension FocusedValues {
    /// The key window's tabs, for the menu bar's tab commands.
    @Entry var windowTabs: WindowTabs?
}

extension Workspace {
    /// The screen a step is on with the sidebar's icon and name for it: the head of the window's breadcrumb, and the
    /// mark on a tab.
    func placeCrumb(of entry: Navigator.Entry) -> Crumb {
        switch Screen(entry) {
        case .course(let id): Crumb(title: course(id)?.title ?? "", symbol: course(id)?.file.course.icon, dot: accent(id).color)
        case .semester(let id):
            { let semester = transcript.semesters.first { $0.id == id }
              return Crumb(title: semester?.title ?? "", symbol: semester?.term == .credited ? "checkmark.seal" : "folder") }()
        case .grades: Crumb(title: String(localized: .rootNavGrades), symbol: "chart.line.uptrend.xyaxis")
        case .requirements: Crumb(title: String(localized: .rootNavRequirements), symbol: "flag")
        case .people: Crumb(title: String(localized: .rootNavPeople), symbol: "person")
        case .codes: Crumb(title: String(localized: .rootNavCodes), symbol: "number")
        case .settings: Crumb(title: String(localized: .rootNavSettings), symbol: "gearshape")
        // The address itself, as the page says it can't be found: not today's, which the page no longer shows.
        case .missing: Crumb(title: entry.link.string, symbol: "questionmark.folder")
        case .today: Crumb(title: String(localized: .rootNavToday), symbol: "house")
        }
    }

    /// The name on a tab behind the one in front: the session, note, file or person it shows, else its screen's name.
    /// A course's section alone ("노트") says less than the course. Nil for Today, whose house says it.
    func tabTitle(of entry: Navigator.Entry) -> String? {
        switch entry.link.kind {
        case .today: nil
        case .session, .unit, .note, .material, .assignment, .exam, .problemSet, .person: itemName(of: entry) ?? placeCrumb(of: entry).title
        default: placeCrumb(of: entry).title
        }
    }
}

#if os(macOS)
/// The window's tabs in its toolbar row: the tab in front is the breadcrumb of where it is, with a close button; the
/// others are an icon and a short name, then icons alone, then a menu, as the row runs out (`TabFit`). A + at the end
/// opens Today in a new tab.
struct TabBar: View {
    let tabs: WindowTabs
    let workspace: Workspace
    /// The tab in front's whole trail: its screen, then what the screen added.
    let crumbs: [Crumb]
    /// The row's width for everything here, the + included.
    let room: CGFloat
    let moveToWindow: (UUID) -> Void
    /// The other tabs at full width, measured.
    @State private var widths: [UUID: CGFloat] = [:]
    @State private var frontWidth: CGFloat = 0
    @State private var moreWidth: CGFloat = 0
    @State private var frames: [UUID: CGRect] = [:]
    @State private var dragged: (id: UUID, start: CGFloat)?
    @State private var dragOffset: CGFloat = 0

    static let gap = Theme.Space.s
    static let icon = Theme.Size.toolbarButton

    var body: some View {
        let others = tabs.ids.filter { $0 != tabs.selected }
        let space = room - Theme.Size.toolbarButton - Self.gap
        let fit = TabFit.layout(room: space, selected: frontWidth, others: others.map { widths[$0] ?? Self.icon },
                                icon: Self.icon, gap: Self.gap, more: moreWidth)
        let shown = Array(others.prefix(fit.shown))
        let hidden = Array(others.dropFirst(fit.shown))
        let row = tabs.ids.filter { $0 == tabs.selected || shown.contains($0) }
        let othersWidth = shown.reduce(0) { $0 + (fit.iconsOnly ? Self.icon : widths[$1] ?? Self.icon) }
        let menuWidth = hidden.isEmpty ? 0 : moreWidth + Self.gap
        let crumbRoom = space - othersWidth - Self.gap * CGFloat(shown.count) - menuWidth - frontChrome
        HStack(spacing: Self.gap) {
            ForEach(row, id: \.self) { id in
                Group {
                    if id == tabs.selected {
                        let trail = max(Breadcrumb.minWidth, crumbRoom)
                        // Its own width while it fits: offered the row, the trail's frame would take all of it, and
                        // held to its measured width a fraction short, it cut the course's name.
                        if frontWidth <= trail + frontChrome {
                            front(crumbRoom: trail).fixedSize()
                        } else {
                            front(crumbRoom: trail).frame(width: trail + frontChrome)
                        }
                    } else {
                        // At their measured width: `TabFit` already made room, and squeezed they'd cut their names.
                        tab(id, iconOnly: fit.iconsOnly).fixedSize()
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[id] = $0 }
                .offset(x: dragged?.id == id ? dragOffset : 0)
                .zIndex(dragged?.id == id ? 1 : 0)
                .simultaneousGesture(drag(id, row: row))
                .contextMenu { menu(id) }
            }
            if !hidden.isEmpty { more(hidden) }
            Button(.tabsNew, systemImage: "plus") { tabs.open() }
                .labelStyle(.iconOnly)
                .buttonStyle(.toolbar)
                .help(Text(.tabsNewHelp))
        }
        .coordinateSpace(.named(Self.space))
        .frame(width: max(0, room), alignment: .leading)
        .background { measures(others) }
        .animation(.snappy(duration: 0.25), value: tabs.ids)
        .animation(.snappy(duration: 0.25), value: fit)
    }

    static let space = "tabs"

    /// The front tab's capsule around its trail: the leading inset and the close button with its gap.
    var frontChrome: CGFloat {
        Theme.Space.m + (tabs.count > 1 ? Theme.Space.xs + Self.closeSize + Theme.Space.xs : Theme.Space.m)
    }

    static let closeSize = Theme.Size.tile

    @ViewBuilder func front(crumbRoom: CGFloat) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Breadcrumb(crumbs: crumbs, foldWidth: crumbRoom, maxWidth: crumbRoom)
            // Not on a lone tab: there it would close the window, which the window's own button already does.
            if tabs.count > 1 { closeButton(tabs.selected) }
        }
        .padding(.leading, Theme.Space.m)
        .padding(.trailing, tabs.count > 1 ? Theme.Space.xs : Theme.Space.m)
        .frame(height: Theme.Size.toolbarButton)
        .tabSurface(front: true)
    }

    func closeButton(_ id: UUID) -> some View {
        Button { tabs.close(id) } label: {
            Image(systemName: "xmark").font(Theme.Glyph.small)
                .frame(width: Self.closeSize, height: Self.closeSize)
                .contentShape(.circle)
        }
        .buttonStyle(.pointing(.plain))
        .foregroundStyle(Theme.Palette.chromeText)
        .help(Text(.tabsCloseHelp))
        .accessibilityLabel(Text(.tabsClose))
    }

    func tab(_ id: UUID, iconOnly: Bool) -> some View {
        let entry = tabs.navigator(id)?.current ?? Navigator.Entry(link: .place(.today))
        let title = workspace.tabTitle(of: entry)
        return Button { tabs.select(id) } label: {
            label(entry, title: iconOnly ? nil : title)
        }
        .buttonStyle(.pointing(.plain))
        .help(title ?? workspace.placeCrumb(of: entry).title)
        .accessibilityLabel(title ?? workspace.placeCrumb(of: entry).title)
    }

    /// A tab behind the front one: its icon, and its name unless it has none or the row is short.
    @ViewBuilder func label(_ entry: Navigator.Entry, title: String?) -> some View {
        let place = workspace.placeCrumb(of: entry)
        Group {
            if let title {
                HStack(spacing: Theme.Space.tight) {
                    icon(place)
                    CappedWidth(width: Theme.Size.tabName) { Text(title).lineLimit(1) }
                }
                .padding(.leading, Theme.Space.s)
                .padding(.trailing, Theme.Space.m)
            } else {
                icon(place).frame(width: Self.icon)
            }
        }
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.chromeText)
        .frame(height: Theme.Size.toolbarButton)
        .tabSurface(front: false)
        .contentShape(.capsule)
    }

    @ViewBuilder func icon(_ place: Crumb) -> some View {
        if let dot = place.dot {
            CourseMark(icon: place.symbol, color: dot)
        } else {
            LineIcon(symbol: place.symbol ?? "questionmark.folder").foregroundStyle(Theme.Palette.chromeIcon)
        }
    }

    func more(_ hidden: [UUID]) -> some View {
        Menu {
            ForEach(hidden, id: \.self) { id in
                let entry = tabs.navigator(id)?.current ?? Navigator.Entry(link: .place(.today))
                let place = workspace.placeCrumb(of: entry)
                Button(workspace.tabTitle(of: entry) ?? place.title, systemImage: place.symbol ?? CourseMark.defaultIcon) { tabs.select(id) }
            }
        } label: {
            moreLabel(hidden.count)
        }
        .menuStyle(.button)
        .buttonStyle(.pointing(.plain))
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text(.tabsMoreHelp))
    }

    func moreLabel(_ n: Int) -> some View {
        HStack(spacing: Theme.Space.tight) {
            Text(.tabsMore(n))
            Image(systemName: "chevron.down").font(Theme.Glyph.small)
        }
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.chromeText)
        .toolbarField()
    }

    func menu(_ id: UUID) -> some View {
        Group {
            Button(.tabsClose) { tabs.close(id) }
            Button(.tabsCloseOthers) { tabs.closeOthers(than: id) }.disabled(tabs.count < 2)
            Divider()
            Button(.tabsMoveToWindow) { moveToWindow(id) }.disabled(tabs.count < 2)
        }
    }

    /// What every tab would take at full width, drawn once out of sight: a tab drawn as an icon can't tell how wide
    /// its name would make it.
    func measures(_ others: [UUID]) -> some View {
        ZStack {
            front(crumbRoom: .infinity).fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { frontWidth = $0 }
            ForEach(others, id: \.self) { id in
                let entry = tabs.navigator(id)?.current ?? Navigator.Entry(link: .place(.today))
                label(entry, title: workspace.tabTitle(of: entry)).fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { widths[id] = $0 }
            }
            // Two digits: the menu's width hardly changes with its count.
            moreLabel(max(others.count, 10)).fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { moreWidth = $0 }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Drags a tab along the row; passing a neighbor's middle swaps them, as in Safari.
    func drag(_ id: UUID, row: [UUID]) -> some Gesture {
        DragGesture(minimumDistance: Theme.Space.xs, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard let frame = frames[id] else { return }
                if dragged?.id != id { dragged = (id, frame.minX) }
                let others = row.filter { $0 != id }
                let before = others.filter { (frames[$0]?.midX ?? 0) < value.location.x }.count
                var rest = tabs.ids.filter { $0 != id }
                let index: Int = if before < others.count { rest.firstIndex(of: others[before]) ?? 0 }
                    else { others.last.flatMap { rest.firstIndex(of: $0) }.map { $0 + 1 } ?? rest.count }
                rest.insert(id, at: index)
                if rest != tabs.ids { tabs.move(id, to: index) }
                // The tab follows the pointer from where it was picked up, whatever place the row now gives it.
                dragOffset = value.translation.width - ((frames[id]?.minX ?? frame.minX) - (dragged?.start ?? frame.minX))
            }
            .onEnded { _ in
                withAnimation(.snappy(duration: 0.2)) {
                    dragged = nil
                    dragOffset = 0
                }
            }
    }
}

/// A short name: its own width up to `width`, cut there. Not `frame(maxWidth:)`, which under `fixedSize` lets the
/// text run at full length past the frame.
private struct CappedWidth: Layout {
    let width: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: min(proposal.width ?? width, width), height: proposal.height)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

private extension View {
    /// The front tab stands out from the frame as a picked choice does; the others are washed like the search field.
    func tabSurface(front: Bool) -> some View {
        background(Theme.Palette.text.opacity(front ? Theme.Opacity.tint : Theme.Opacity.wash), in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.Palette.text.opacity(Theme.Opacity.edge)) }
    }
}
#endif
