import SwiftUI

/// Which list column a `ColumnSplit` holds. Hiding one by hand is remembered for its kind, so every window and pane
/// showing that kind follows it (#62).
enum ColumnKind: String, CaseIterable {
    case courseSections, settingsTabs, people, quizScope

    /// A column of a few fixed sections, rather than a list that grows: the menu names it 구역 열, not 목록 열.
    var holdsSections: Bool { self == .courseSections || self == .settingsTabs }
}

/// How a list column beside a page folds where both don't fit (#43, #62): a column of fixed sections leaves the page
/// alone; a list that grows (people, a quiz's scope) is the page while there is nothing to show beside it.
enum ColumnFold: Equatable {
    case sections
    case list(showingPage: Bool)
}

/// Where a list column is, from the room beside it and the person's choice (#62). The column docks beside the page
/// only where the page keeps `ColumnSplit.pageRoom` and it isn't hidden by hand; otherwise it is folded, and the button
/// at the page's corner brings it back.
struct ColumnFit: Equatable {
    var roomy: Bool
    var collapsed: Bool
    /// A growing list with no page to show beside it.
    var nothingBeside = false

    init(roomy: Bool, collapsed: Bool, fold: ColumnFold = .sections) {
        self.roomy = roomy
        self.collapsed = collapsed
        if case .list(false) = fold { nothingBeside = true }
    }

    var docked: Bool { roomy && !collapsed }
    /// Folded for want of room with nothing beside it: the list is the page, and no button is needed to reach it.
    /// Hidden by hand where it fits, the page shows its empty state and the button brings the list back.
    var listAlone: Bool { !roomy && nothingBeside }
    var showsPage: Bool { !listAlone }

    enum Show: Equatable { case dock, overlay }
    /// Showing a folded column again, by its button or the menu: back beside the page where it fits, so the choice to
    /// hide it is undone; over the page for the moment where it doesn't, the choice kept.
    var show: Show { roomy ? .dock : .overlay }
}

/// The columns hidden by hand, on this device: a choice about the screen, not GIST data, so in `UserDefaults` rather
/// than `settings.json`. One object for the app, so every window and pane follows a change at once.
@MainActor @Observable final class ColumnPrefs {
    static let shared = ColumnPrefs(defaults: .standard)
    @ObservationIgnored private let defaults: UserDefaults?
    private var collapsed: Set<ColumnKind>

    /// Nil defaults keep the choice in memory only: renders and tests, which mustn't write the installed app's.
    init(defaults: UserDefaults?, collapsed: Set<ColumnKind> = []) {
        self.defaults = defaults
        self.collapsed = defaults.map { d in Set(ColumnKind.allCases.filter { d.bool(forKey: Self.key($0)) }) } ?? collapsed
    }

    static func key(_ kind: ColumnKind) -> String { "columnCollapsed.\(kind.rawValue)" }

    func isCollapsed(_ kind: ColumnKind) -> Bool { collapsed.contains(kind) }

    func set(_ kind: ColumnKind, collapsed on: Bool) {
        if on { collapsed.insert(kind) } else { collapsed.remove(kind) }
        defaults?.set(on, forKey: Self.key(kind))
    }
}

/// The menu bar's 구역 열 보기·숨기기 for the focused pane's outermost column, which the pane's screen leaves in its
/// `CrumbTrail` while it is on screen.
struct ColumnCommand {
    var kind: ColumnKind
    /// Beside the page, or open over it.
    var shown: Bool
    var toggle: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var columnCommand: ColumnCommand?
}

/// The labels of the column buttons on screen, for the screen fit check to find them.
struct ColumnButtonLabels: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) { value += nextValue() }
}

extension EnvironmentValues {
    /// Inside a `ColumnSplit` whose column isn't docked beside the page: what each held for the other now has to be in it.
    @Entry var columnFolded = false
    /// How many column buttons sit along the top-leading corner of this view: what starts there clears their row
    /// (`clearOfColumnButtons(inset:)`). Nested splits (a quiz's scope in a folded course) line theirs up after.
    @Entry var columnButtons = 0
    /// Closes the folded column open over the page, for a row picked in it that leaves the window's place as it was.
    @Entry var closeColumn: @MainActor () -> Void = {}
    @Entry var columnPrefs: ColumnPrefs?
    /// Set by an outer `ColumnSplit` on what it holds: only the outermost column answers the menu bar.
    @Entry var insideColumnSplit = false
    /// False in a pane of several that isn't focused, which leaves the menu bar's column command to the focused one.
    @Entry var paneFocused = true
}

extension View {
    /// For what starts at the top-leading corner under the column buttons: pushed down so the row of buttons clears it,
    /// `inset` being how far down it already starts. Nothing changes where no button sits over it.
    func clearOfColumnButtons(inset: CGFloat) -> some View { modifier(ClearOfColumnButtons(inset: inset)) }

    /// A list column's own ground: the window's beside the page, none on the glass of the column open over it.
    func columnBackground() -> some View { modifier(ColumnBackground()) }
}

private struct ClearOfColumnButtons: ViewModifier {
    let inset: CGFloat
    @Environment(\.columnButtons) private var buttons

    func body(content: Content) -> some View {
        content.padding(.top, buttons > 0 ? max(ColumnSplit<EmptyView, EmptyView>.buttonRow - inset, 0) : 0)
    }
}

private struct ColumnBackground: ViewModifier {
    @Environment(\.onGlass) private var onGlass

    func body(content: Content) -> some View {
        // Up under the window's top row like the divider beside it.
        content.background { if !onGlass { Theme.Palette.window.ignoresSafeArea() } }
    }
}

/// A list column, its divider and a page (#43). The column docks beside the page where the page keeps `pageRoom` and
/// it isn't hidden by hand; otherwise a button at the page's top-leading corner slides the same column over the page
/// on glass, or docks it back where it fits (#62). The same button on the docked column hides it.
struct ColumnSplit<Column: View, Content: View>: View {
    let kind: ColumnKind
    var width: CGFloat = Theme.Size.courseColumn
    var fold: ColumnFold = .sections
    @ViewBuilder var column: Column
    @ViewBuilder var content: Content
    @Environment(\.revealsOverflow) private var revealsOverflow
    @Environment(\.columnButtons) private var outerButtons
    @Environment(\.columnPrefs) private var givenPrefs
    @Environment(\.place) private var place
    @Environment(\.insideColumnSplit) private var nested
    @Environment(\.paneFocused) private var paneFocused
    @Environment(CrumbTrail.self) private var trail: CrumbTrail?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Measured, unlike `Fold`: the side-by-side form can't push a pane out (the page goes down to nothing), so its
    // first pass at the old width costs nothing, and only the width the page is left decides.
    @State private var roomy = true
    @State private var paneWidth: CGFloat = 0
    @State private var opened = false
    @State private var owner = UUID()

    /// What a page needs beside the column; less, and the column folds.
    static var pageRoom: CGFloat { 440 }
    /// The row the buttons sit in at the top: a toolbar-high button and `Space.s` above and below it.
    static var buttonRow: CGFloat { Theme.Size.toolbarButton + Theme.Space.s * 2 }
    /// How much of the pane the open column leaves uncovered at its trailing side, to click back to the page.
    static var pageEdge: CGFloat { buttonRow }

    var prefs: ColumnPrefs { givenPrefs ?? .shared }
    var fit: ColumnFit { ColumnFit(roomy: roomy, collapsed: prefs.isCollapsed(kind), fold: fold) }
    var buttons: Int { outerButtons + 1 }

    /// Over the page: only while folded, so a column that docks or becomes the page is never left open.
    var open: Bool {
        var asked = opened
        #if DEBUG && os(macOS)
        // Window snapshots and renders draw it open, as its button would (`FOLIO_SNAPSHOT_COLUMN=open`).
        asked = asked || SnapshotDriver.shared.columnOpen
        #endif
        return asked && !fit.docked && !fit.listAlone
    }

    var body: some View {
        let fit = fit
        HStack(spacing: 0) {
            if fit.docked || fit.listAlone {
                column
                    .frame(width: fit.docked ? width : nil)
                    .frame(maxWidth: fit.docked ? nil : .infinity, maxHeight: .infinity)
                    .environment(\.columnFolded, !fit.docked)
                    // Alone, the list has no button of its own: the page it stands in for is what one would bring back.
                    .environment(\.columnButtons, fit.docked ? buttons : outerButtons)
                    .transition(.move(edge: .leading))
            }
            if fit.docked { ColumnDivider() }
            if fit.showsPage {
                content
                    // minWidth 0: a page's fixed-width rows must never set the column's minimum. When that
                    // minimum plus a side column exceeds the window, AppKit loops on constraints and kills the
                    // app. A fit check lifts it to see the page overflow, which this otherwise clips.
                    .frame(minWidth: revealsOverflow ? nil : 0, maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.columnFolded, !fit.docked)
                    // Beside a docked column the buttons sit over the column, not the page.
                    .environment(\.columnButtons, fit.docked ? 0 : buttons)
                    .accessibilityHidden(open)
            }
        }
        .environment(\.insideColumnSplit, true)
        .overlay(alignment: .topLeading) {
            if !fit.listAlone { overlay(fit) }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { w in
            paneWidth = w
            roomy = w >= width + 1 + Self.pageRoom
        }
        // Room again, or a docked column: nothing is left over the page.
        .onChange(of: fit.docked) { _, docked in if docked { opened = false } }
        .onChange(of: fit.listAlone) { _, alone in if alone { opened = false } }
        // A row picked in the open column moves the window, which is where every pick goes (`\.openLink`).
        .onChange(of: place) { close() }
        .onChange(of: registration, initial: true) { _, _ in register() }
        .onDisappear { trail?.clearColumn(owner: owner) }
    }

    func overlay(_ fit: ColumnFit) -> some View {
        ZStack(alignment: .topLeading) {
            if open {
                scrim
                panel
            }
            button(fit)
                .padding(.leading, Theme.Space.s + CGFloat(outerButtons) * (Theme.Size.toolbarButton + Theme.Space.s))
                .padding(.top, Theme.Space.s)
        }
        .animation(.snappy(duration: 0.25), value: open)
    }

    /// Dims the page and takes the click that closes the column, which a click on the page would otherwise act on.
    var scrim: some View {
        Color.black.opacity(Theme.Opacity.scrim)
            .contentShape(.rect)
            .onTapGesture(perform: close)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(.commonClose))
            .transition(.opacity)
    }

    /// The column as it is docked, on glass over the page: its usual width, short of the pane's trailing edge.
    var panel: some View {
        let panelWidth = max(min(width, paneWidth - Theme.Space.s - Self.pageEdge), 0)
        let closing: @MainActor () -> Void = close
        return column
            .environment(\.onGlass, true)
            .environment(\.columnFolded, false)
            .environment(\.columnButtons, buttons)
            .environment(\.closeColumn, closing)
            .frame(width: panelWidth)
            .frame(maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: Theme.Radius.floating))
            .floatingGlass()
            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
            .padding([.top, .leading, .bottom], Theme.Space.s)
            // Esc, on the iPad's keyboard too; a hidden view's shortcut doesn't fire, a clear one's does.
            .background { Button("", action: close).keyboardShortcut(.cancelAction).opacity(0).allowsHitTesting(false).accessibilityHidden(true) }
            .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
    }

    func button(_ fit: ColumnFit) -> some View {
        let shown = fit.docked || open
        let label = Self.label(kind, shown: shown)
        return Button(action: toggle) {
            Image(systemName: "sidebar.leading")
                .font(Theme.Glyph.toolbar)
                .foregroundStyle(Theme.Palette.chromeIcon)
                .frame(width: Theme.Size.toolbarButton, height: Theme.Size.toolbarButton)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.pointing(.plain))
        .help(label)
        .accessibilityLabel(label)
        .preference(key: ColumnButtonLabels.self, value: [label])
    }

    static func label(_ kind: ColumnKind, shown: Bool) -> String {
        switch (kind.holdsSections, shown) {
        case (true, true): String(localized: .designColumnHideSections)
        case (true, false): String(localized: .designColumnShowSections)
        case (false, true): String(localized: .designColumnHideList)
        case (false, false): String(localized: .designColumnShowList)
        }
    }

    /// The button and the menu bar's command: hides a docked column by hand, closes it open over the page, and
    /// otherwise shows it as `ColumnFit.show` says.
    func toggle() {
        let fit = fit
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            if fit.docked {
                prefs.set(kind, collapsed: true)
            } else if open {
                opened = false
            } else if fit.listAlone {
                return
            } else {
                switch fit.show {
                case .dock: prefs.set(kind, collapsed: false)
                case .overlay: opened = true
                }
            }
        }
    }

    func close() {
        guard open else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { opened = false }
    }

    /// What the menu bar's command shows, which changes with the column.
    var registration: [Bool] { [nested, paneFocused, fit.docked || open, fit.listAlone] }

    func register() {
        guard let trail else { return }
        guard !nested, paneFocused, !fit.listAlone else { return trail.clearColumn(owner: owner) }
        trail.setColumn(ColumnCommand(kind: kind, shown: fit.docked || open, toggle: toggle), owner: owner)
    }
}

/// A row of a list column, or a button in it that finishes with the column (a quiz's start): picking it also closes the
/// column where it is open over the page, even when the pick leaves the window where it was. Its own view, so it
/// reads the `closeColumn` the open column is given, which the screen that draws the column doesn't see.
struct ColumnPick<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    @Environment(\.closeColumn) private var closeColumn

    var body: some View {
        Button {
            action()
            closeColumn()
        } label: { label }
    }
}
