import SwiftUI

enum ColumnKind: String, CaseIterable {
    case courseSections, settingsTabs, people, quizScope

    var holdsSections: Bool { self == .courseSections || self == .settingsTabs }
}

enum ColumnFold: Equatable {
    case sections
    case list(showingPage: Bool)
}

struct ColumnFit: Equatable {
    var roomy: Bool
    var collapsed: Bool
    var nothingBeside = false

    init(roomy: Bool, collapsed: Bool, fold: ColumnFold = .sections) {
        self.roomy = roomy
        self.collapsed = collapsed
        if case .list(false) = fold { nothingBeside = true }
    }

    var docked: Bool { roomy && !collapsed }
    var listAlone: Bool { !roomy && nothingBeside }
    var showsPage: Bool { !listAlone }

    enum Show: Equatable { case dock, overlay }
    var show: Show { roomy ? .dock : .overlay }
}

@MainActor @Observable final class ColumnPrefs {
    private(set) var collapsed: Set<ColumnKind>
    @ObservationIgnored private let memory: ColumnMemory?

    // 렌더와 테스트가 새 칸의 시작 상태를 바꾸면 안 되므로, 기억할 곳이 없으면 이 칸 안에서만 기억한다.
    init(collapsed: Set<ColumnKind> = [], memory: ColumnMemory? = nil) {
        self.collapsed = collapsed
        self.memory = memory
    }

    static let loose = ColumnMemory.shared.newPane()

    func isCollapsed(_ kind: ColumnKind) -> Bool { collapsed.contains(kind) }

    func set(_ kind: ColumnKind, collapsed on: Bool) {
        if on { collapsed.insert(kind) } else { collapsed.remove(kind) }
        memory?.remember(kind, collapsed: on)
    }
}

@MainActor final class ColumnMemory {
    // 테스트 호스트, 창 스냅숏 실행, 크기 측정 실행은 설치된 앱과 bundle ID가 같아서 defaults도 사용자의 것을 쓴다.
    // 그러면 사용자가 숨긴 열이 측정이나 그림을 바꾸고, 실행이 숨긴 열은 사용자에게 계속 숨겨진다.
    static let shared = ColumnMemory(defaults: isolated ? nil : .standard)
    private static var isolated: Bool {
        #if DEBUG && os(macOS)
        if SnapshotDriver.directory != nil { return true }
        #endif
        #if os(macOS) && (DEBUG || RESIZE_PROBE)
        if ResizeProbe.file != nil { return true }
        #endif
        return LocalFolders.isIsolated()
    }
    private let defaults: UserDefaults?
    private(set) var last: Set<ColumnKind>

    init(defaults: UserDefaults?, collapsed: Set<ColumnKind> = []) {
        self.defaults = defaults
        last = defaults.map { d in Set(ColumnKind.allCases.filter { d.bool(forKey: Self.key($0)) }) } ?? collapsed
    }

    static func key(_ kind: ColumnKind) -> String { "columnCollapsed.\(kind.rawValue)" }

    func remember(_ kind: ColumnKind, collapsed on: Bool) {
        if on { last.insert(kind) } else { last.remove(kind) }
        defaults?.set(on, forKey: Self.key(kind))
    }

    func newPane() -> ColumnPrefs { ColumnPrefs(collapsed: last, memory: self) }

    // 나중 빌드가 없앤 종류가 있어도 요청 전체와 창이 실패하지 않도록, 원래 이름으로 받아 모르는 종류만 건너뛴다.
    func pane(_ kinds: [String]?) -> ColumnPrefs {
        guard let kinds else { return newPane() }
        return ColumnPrefs(collapsed: Set(kinds.compactMap(ColumnKind.init(rawValue:))), memory: self)
    }
}

extension ColumnPrefs {
    var names: [String] { collapsed.map(\.rawValue).sorted() }
}

struct ColumnCommand {
    var kind: ColumnKind
    var shown: Bool
    var toggle: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var columnCommand: ColumnCommand?
}

struct ColumnButtonLabels: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) { value += nextValue() }
}

extension EnvironmentValues {
    @Entry var columnFolded = false
    @Entry var columnButtons = 0
    @Entry var closeColumn: @MainActor () -> Void = {}
    @Entry var columnPrefs: ColumnPrefs?
    @Entry var insideColumnSplit = false
    @Entry var paneFocused = true
}

extension View {
    func clearOfColumnButtons(inset: CGFloat) -> some View { modifier(ClearOfColumnButtons(inset: inset)) }

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
        content.background { if !onGlass { Theme.Palette.window.ignoresSafeArea() } }
    }
}

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
    @State private var roomy = true
    @State private var paneWidth: CGFloat = 0
    @State private var opened = false
    @State private var owner = UUID()

    static var pageRoom: CGFloat { 440 }
    static var buttonRow: CGFloat { Theme.Size.toolbarButton + Theme.Space.s * 2 }
    static var pageEdge: CGFloat { buttonRow }

    var prefs: ColumnPrefs { givenPrefs ?? .loose }
    var fit: ColumnFit { ColumnFit(roomy: roomy, collapsed: prefs.isCollapsed(kind), fold: fold) }
    var buttons: Int { outerButtons + 1 }

    var open: Bool {
        var asked = opened
        #if DEBUG && os(macOS)
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
                    .environment(\.columnButtons, fit.docked ? buttons : outerButtons)
                    .transition(.move(edge: .leading))
            }
            if fit.docked { ColumnDivider() }
            if fit.showsPage {
                content
                    // minWidth를 0으로 두어 본문의 고정 폭 행이 열의 최소 폭을 정하지 못하게 한다. 그 최소 폭과 옆 열의
                    // 합이 창보다 크면 AppKit이 constraint 계산을 반복하다 앱이 종료된다. 화면 맞춤 검사는 이 제한을
                    // 풀어, 평소에는 잘리는 본문의 넘침을 본다.
                    .frame(minWidth: revealsOverflow ? nil : 0, maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.columnFolded, !fit.docked)
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
        .onChange(of: fit.docked) { _, docked in if docked { opened = false } }
        .onChange(of: fit.listAlone) { _, alone in if alone { opened = false } }
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
        .animation(Theme.Motion.standard, value: open)
    }

    var scrim: some View {
        Color.black.opacity(Theme.Opacity.scrim)
            .contentShape(.rect)
            .onTapGesture(perform: close)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(.commonClose))
            .transition(.opacity)
    }

    var panel: some View {
        let panelWidth = max(min(width, paneWidth - Theme.Space.s - Self.pageEdge), 0)
        let closing: @MainActor () -> Void = close
        return
            column
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
            // iPad 키보드에서도 Esc로 닫는다. 숨긴 뷰의 단축키는 동작하지 않고, 투명한 뷰의 단축키는 동작한다.
            .background {
                Button("", action: close).keyboardShortcut(.cancelAction).opacity(0).allowsHitTesting(false).accessibilityHidden(true)
            }
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

    func toggle() {
        let fit = fit
        withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
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
        withAnimation(reduceMotion ? nil : Theme.Motion.standard) { opened = false }
    }

    var registration: [Bool] { [nested, paneFocused, fit.docked || open, fit.listAlone] }

    func register() {
        guard let trail else { return }
        guard !nested, paneFocused, !fit.listAlone else { return trail.clearColumn(owner: owner) }
        trail.setColumn(ColumnCommand(kind: kind, shown: fit.docked || open, toggle: toggle), owner: owner)
    }
}

// 열을 그리는 화면은 열린 열에 주어진 `closeColumn`을 보지 못하므로, 그 값을 읽도록 별도 뷰로 둔다.
struct ColumnPick<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    @Environment(\.closeColumn) private var closeColumn

    var body: some View {
        Button {
            action()
            closeColumn()
        } label: {
            label
        }
    }
}
