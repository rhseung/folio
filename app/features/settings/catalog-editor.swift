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
                    Caption(String(localized: .letterGradesSymbol)).frame(width: Self.symbolWidth)
                    Caption(String(localized: .letterGradesPoints)).padding(.trailing, Theme.Space.m).frame(width: Self.pointsWidth, alignment: .trailing)
                    Caption(String(localized: .letterGradesCountsIn)).padding(.leading, Theme.Space.xs).frame(width: Self.flagsWidth, alignment: .leading)
                    Caption(String(localized: .courseEditGrading))
                } row: { $g in
                    TextField(String(localized: .letterGradesSymbol), text: $g.symbol).pill(width: Self.symbolWidth, alignment: .center)
                    TextField("—", value: $g.points, format: .number).pill(width: Self.pointsWidth)
                    HStack(spacing: Theme.Space.tight) {
                        ToggleChip("GPA", isOn: $g.countsInGpa)
                        ToggleChip(String(localized: .letterGradesCredits), isOn: $g.countsInCredits)
                        ToggleChip(String(localized: .letterGradesGraduation), isOn: Binding(get: { g.earnsCredits }, set: { g.countsTowardGraduation = $0 }))
                    }
                    .frame(width: Self.flagsWidth, alignment: .leading)
                    ChoiceMenu(selection: Binding(get: { Self.canonical(g.modes) }, set: { g.modes = $0 }), options: Self.modeOptions(g.modes))
                }
                Footnote(String(localized: .letterGradesFootnote))
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
        let fixed: [([GradingMode]?, String)] = [(nil, String(localized: .letterGradesModeAuto)), ([.relative, .absolute], String(localized: .letterGradesModeGraded)), ([.passFail], "S/U"), (GradingMode.allCases, String(localized: .letterGradesModeAll))]
        guard let current = canonical(modes), !fixed.contains(where: { $0.0 == current }) else { return fixed }
        let names: [GradingMode: String] = [.relative: String(localized: .gradingModeRelative), .absolute: String(localized: .gradingModeAbsolute), .passFail: "S/U"]
        return fixed + [(current, current.isEmpty ? String(localized: .commonNone) : current.compactMap { names[$0] }.joined(separator: "·"))]
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
                    .help(Text(.commonDelete))
                }
                .contextMenu { Button(.commonDeleteEllipsis, role: .destructive) { removing = item } }
            }
            CardRow(last: true) {
                Button { items.append(make()) } label: {
                    Label(.commonAdd, systemImage: "plus").foregroundStyle(Theme.Palette.textSecondary)
                }
                .buttonStyle(.pointing(.plain))
            }
        }
        .confirmationDialog(Text(.entityRowsRemoveTitle(removing?[keyPath: name] ?? "")), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { item in
            Button(.commonDelete, role: .destructive) { items.removeAll { $0.id == item.id } }
        } message: { _ in
            Text(.entityRowsRemoveMessage)
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
