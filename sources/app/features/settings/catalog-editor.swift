import FolioDomain
import SwiftUI

struct CatalogEditor: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        let device = workspace.device
        CatalogEditing { $catalog in
            ViewThatFits(in: .horizontal) {
                table($catalog.letterGrades, device: device, wide: true)
                table($catalog.letterGrades, device: device, wide: false)
            }
        }
    }

    func table(_ grades: Binding<[LetterGrade]>, device: DeviceID, wide: Bool) -> some View {
        EntityRows(
            items: grades, name: \.symbol,
            make: { LetterGrade(device: device, at: .now, symbol: "", points: nil, countsInGpa: true, countsInCredits: true) }
        ) {
            Caption(String(localized: .letterGradesSymbol)).frame(width: Self.symbolWidth)
            Caption(String(localized: .letterGradesPoints)).padding(.trailing, Theme.Space.m).frame(
                width: Self.pointsWidth, alignment: .trailing)
            if wide {
                Caption(String(localized: .letterGradesCountsIn)).padding(.leading, Theme.Space.xs).frame(
                    width: Self.flagsWidth, alignment: .leading)
            }
            Caption(String(localized: .courseEditGrading))
        } row: { $g in
            let flags = HStack(spacing: Theme.Space.tight) {
                ToggleChip("GPA", isOn: $g.countsInGpa)
                ToggleChip(String(localized: .letterGradesCredits), isOn: $g.countsInCredits)
                ToggleChip(
                    String(localized: .letterGradesGraduation),
                    isOn: Binding(get: { g.earnsCredits }, set: { g.countsTowardGraduation = $0 }))
            }
            let fields = Group {
                TextField(String(localized: .letterGradesSymbol), text: $g.symbol).pill(width: Self.symbolWidth, alignment: .center)
                TextField("—", value: $g.points, format: .number).pill(width: Self.pointsWidth)
            }
            let modes = ChoiceMenu(
                selection: Binding(get: { Self.canonical(g.modes) }, set: { g.modes = $0 }), options: Self.modeOptions(g.modes))
            if wide {
                fields
                flags.frame(width: Self.flagsWidth, alignment: .leading)
                modes
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(spacing: Theme.Space.s) {
                        fields; modes
                    }
                    flags
                }
            }
        }
    }

    static let symbolWidth: CGFloat = 56
    static let pointsWidth: CGFloat = 64
    static let flagsWidth: CGFloat = 156

    // 같은 방식을 다른 순서로 적은 파일도 그 선택지와 맞도록 `GradingMode.allCases`의 순서로 바꾼다.
    static func canonical(_ modes: [GradingMode]?) -> [GradingMode]? {
        modes.map { m in GradingMode.allCases.filter(m.contains) }
    }

    static func modeOptions(_ modes: [GradingMode]?) -> [([GradingMode]?, String)] {
        let fixed: [([GradingMode]?, String)] = [
            (nil, String(localized: .letterGradesModeAuto)), ([.relative, .absolute], String(localized: .letterGradesModeGraded)),
            ([.passFail], "S/U"), (GradingMode.allCases, String(localized: .letterGradesModeAll)),
        ]
        guard let current = canonical(modes), !fixed.contains(where: { $0.0 == current }) else { return fixed }
        let names: [GradingMode: String] = [
            .relative: String(localized: .gradingModeRelative), .absolute: String(localized: .gradingModeAbsolute), .passFail: "S/U",
        ]
        return fixed + [
            (current, current.isEmpty ? String(localized: .commonNone) : current.compactMap { names[$0] }.joined(separator: "·"))
        ]
    }
}

// 이 앱 버전이 모르는 키도 파일에 남는다.
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
            // 다른 페이지나 설정 창이 저장하면 그 값에서 다시 시작한다. 그러지 않으면 다음 저장이 그 변경을 되돌린다.
            .onChange(of: workspace.catalog) { _, new in catalog = new }
            .task(id: catalog) {
                guard loaded else { return }
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, catalog != workspace.catalog else { return }
                workspace.saveCatalog(catalog)
            }
            // 변경 직후에 닫으면 위의 대기가 취소되므로 남은 것을 저장한다.
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
                    Button {
                        removing = item
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.pointing(.plain))
                    .help(Text(.commonDelete))
                }
                .contextMenu { Button(.commonDeleteEllipsis, role: .destructive) { removing = item } }
            }
            CardRow(last: true) {
                Button {
                    items.append(make())
                } label: {
                    Label(.commonAdd, systemImage: "plus").foregroundStyle(Theme.Palette.textSecondary)
                }
                .buttonStyle(.pointing(.plain))
            }
        }
        .confirmationDialog(
            Text(.entityRowsRemoveTitle(removing?[keyPath: name] ?? "")),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { item in
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
        Button {
            isOn.toggle()
        } label: {
            Chip(title, tone: isOn ? .success : .plain)
        }
        .buttonStyle(.pointing(.plain))
        .opacity(isOn ? 1 : 0.6)
    }
}
