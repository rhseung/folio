import FolioDomain
import SwiftUI

struct CatalogEditor: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        let device = workspace.device
        CatalogEditing { $catalog in
            // No block title: the tab already says 평어. The header row names the columns instead.
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                EntityRows(items: $catalog.letterGrades, name: \.symbol,
                           make: { LetterGrade(device: device, at: .now, symbol: "", points: nil, countsInGpa: true, countsInCredits: true) }) {
                    Caption("기호").frame(width: Self.symbolWidth)
                    Caption("평점").padding(.trailing, Theme.Space.m).frame(width: Self.pointsWidth, alignment: .trailing)
                    Caption("셈하는 곳").padding(.leading, Theme.Space.xs).frame(width: Self.flagsWidth, alignment: .leading)
                    Caption("평가 방식")
                } row: { $g in
                    TextField("기호", text: $g.symbol).pill(width: Self.symbolWidth, alignment: .center)
                    TextField("—", value: $g.points, format: .number).pill(width: Self.pointsWidth)
                    HStack(spacing: Theme.Space.tight) {
                        ToggleChip("GPA", isOn: $g.countsInGpa)
                        ToggleChip("학점", isOn: $g.countsInCredits)
                        ToggleChip("졸업", isOn: Binding(get: { g.earnsCredits }, set: { g.countsTowardGraduation = $0 }))
                    }
                    .frame(width: Self.flagsWidth, alignment: .leading)
                    ChoiceMenu(selection: Binding(get: { Self.canonical(g.modes) }, set: { g.modes = $0 }), options: Self.modeOptions(g.modes))
                }
                Footnote("초록 칩이 켜진 것입니다. GPA는 평점 평균, 학점은 학기 총 학점, 졸업은 졸업 학점과 요건에 셉니다. 평가 방식이 자동이면 평점이 있는 기호는 등급제 과목에, 없는 기호는 어느 과목에나 씁니다.")
            }
        }
    }

    static let symbolWidth: CGFloat = 56
    static let pointsWidth: CGFloat = 64
    static let flagsWidth: CGFloat = 156

    /// In the order of `GradingMode.allCases`, so a file that lists the same modes in another order still matches its option.
    static func canonical(_ modes: [GradingMode]?) -> [GradingMode]? {
        modes.map { m in GradingMode.allCases.filter(m.contains) }
    }

    /// The fixed choices, plus the stored set when it is none of them, so the menu never shows an empty label.
    static func modeOptions(_ modes: [GradingMode]?) -> [([GradingMode]?, String)] {
        let fixed: [([GradingMode]?, String)] = [(nil, "자동"), ([.relative, .absolute], "등급제"), ([.passFail], "S/U"), (GradingMode.allCases, "모두")]
        guard let current = canonical(modes), !fixed.contains(where: { $0.0 == current }) else { return fixed }
        let names: [GradingMode: String] = [.relative: "상대평가", .absolute: "절대평가", .passFail: "S/U"]
        return fixed + [(current, current.isEmpty ? "없음" : current.compactMap { names[$0] }.joined(separator: "·"))]
    }
}

/// A copy of catalog.json saved once typing pauses; keys this app version doesn't know stay in the file.
struct CatalogEditing<Content: View>: View {
    @Environment(Workspace.self) private var workspace
    @State private var catalog = Catalog()
    @State private var loaded = false
    @ViewBuilder let content: (Binding<Catalog>) -> Content

    var body: some View {
        content($catalog)
            .onAppear {
                catalog = workspace.catalog
                loaded = true
            }
            // Another page or the settings window saved: start from that, or the next save would undo it.
            .onChange(of: workspace.catalog) { _, new in catalog = new }
            .task(id: catalog) {
                guard loaded else { return }
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, catalog != workspace.catalog else { return }
                workspace.saveCatalog(catalog)
            }
            // Closing right after a change cancels the wait above; save what was left.
            .onDisappear { if loaded, catalog != workspace.catalog { workspace.saveCatalog(catalog) } }
    }
}

struct EntityRows<E: Entity, Header: View, Row: View>: View {
    @Binding var items: [E]
    let name: KeyPath<E, String>
    let make: () -> E
    @ViewBuilder let header: Header
    @ViewBuilder let row: (Binding<E>) -> Row
    @State private var removing: E?

    var body: some View {
        Card {
            HStack(spacing: Theme.Space.s) { header }
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, Theme.Space.m)
                .padding(.bottom, Theme.Space.xs)
            ForEach($items) { $item in
                CardRow {
                    HStack(spacing: Theme.Space.s) { row($item) }
                    Spacer(minLength: 0)
                    Button { removing = item } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.pointing(.plain))
                    .help("삭제")
                }
                .contextMenu { Button("삭제…", role: .destructive) { removing = item } }
            }
            CardRow(last: true) {
                Button { items.append(make()) } label: {
                    Label("추가", systemImage: "plus").foregroundStyle(Theme.Palette.textSecondary)
                }
                .buttonStyle(.pointing(.plain))
            }
        }
        .confirmationDialog("‘\(removing?[keyPath: name] ?? "")’을 지울까요?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { item in
            Button("삭제", role: .destructive) { items.removeAll { $0.id == item.id } }
        } message: { _ in
            Text("이 항목을 쓰는 과목에서는 표시가 비게 됩니다.")
        }
    }
}

struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Button { isOn.toggle() } label: { Chip(title, tone: isOn ? .success : .plain) }
            .buttonStyle(.pointing(.plain))
            .opacity(isOn ? 1 : 0.6)
    }
}
